import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

/// Whether the palm-rest sensor should be sampled right now. Pure, so every rule is tested.
struct ChassisTapPower: Equatable, Sendable {
    var sensorPresent: Bool
    var enabled: Bool
    var dictationRunning: Bool
    var screenLocked = false
    var displayAsleep = false
    var systemAsleep = false
    /// Nil on a Mac with no battery reading.
    var batteryPercent: Int?
    var onBattery = false

    /// Sampling stops below this charge on battery.
    static let lowBattery = 10

    var shouldSample: Bool {
        guard sensorPresent, enabled, dictationRunning else { return false }
        guard !screenLocked, !displayAsleep, !systemAsleep else { return false }
        if onBattery, let batteryPercent, batteryPercent < Self.lowBattery { return false }
        return true
    }

    /// Why it isn't sampling, for the log.
    var reason: String {
        if !sensorPresent { return "no palm-rest sensor on this Mac" }
        if !enabled { return "off in Settings" }
        if !dictationRunning { return "dictation paused" }
        if screenLocked { return "screen locked" }
        if displayAsleep { return "display asleep" }
        if systemAsleep { return "Mac asleep" }
        if onBattery, let batteryPercent, batteryPercent < Self.lowBattery { return "battery under \(Self.lowBattery)%" }
        return "sampling"
    }
}

/// The chassis tap trigger: a double tap on the palm rest starts hands-free dictation, and
/// another ends it. Off by default. Never uses the microphone.
///
/// The sensor is sampled only while `ChassisTapPower.shouldSample` holds. A double tap within
/// 0.4 s of a key press or a click is typing or clicking, and is dropped; the last-input ages
/// come from the window server and need no permission (checked with a grant-less app on macOS
/// 15.2).
@MainActor
final class ChassisTapTrigger {
    static let enabledKey = "chassisTapEnabled"

    private let onTap: @MainActor () -> Void
    private let defaults: UserDefaults
    private var power: ChassisTapPower
    private var sensor: SPUAccelerometer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var batteryTimer: Timer?

    init(defaults: UserDefaults = .standard, onTap: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.onTap = onTap
        power = ChassisTapPower(
            sensorPresent: SPUAccelerometer.isAvailable,
            enabled: defaults.bool(forKey: Self.enabledKey),
            dictationRunning: false
        )
        observe()
        readBattery()
    }

    static var isAvailable: Bool { SPUAccelerometer.isAvailable }

    var isSampling: Bool { sensor != nil }

    /// Follows the setting.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        update { $0.enabled = enabled }
    }

    /// Follows the dictation pipeline: sampling only while dictation is running, not paused.
    func setDictationRunning(_ running: Bool) {
        update { $0.dictationRunning = running }
    }

    /// Applies a change to the power state. Internal so the live check can stand in for a
    /// screen lock without posting the system's real notification to every app.
    func update(_ change: (inout ChassisTapPower) -> Void) {
        change(&power)
        if power.shouldSample, sensor == nil {
            startSensor()
        } else if !power.shouldSample, let sensor {
            sensor.stop()
            self.sensor = nil
            Log.tap.info("Palm-rest sensor stopped: \(self.power.reason, privacy: .public)")
        }
    }

    // MARK: Private

    private func startSensor() {
        let sensor = SPUAccelerometer()
        let pipeline = TapPipeline(setRate: { [weak sensor] rate in sensor?.setRate(rate) }) { [weak self] first in
            // Back on the main thread, where the hotkey monitor delivers its own events.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.accept(firstKnock: first) }
            }
        }
        sensor.onSample = { t, a in pipeline.process(t: t, a) }
        do {
            try sensor.start(rate: .idle)
            self.sensor = sensor
            Log.tap.info("Palm-rest sensor sampling")
        } catch {
            Log.tap.error("Palm-rest sensor would not start: \(String(describing: error), privacy: .public)")
            power.sensorPresent = false
        }
    }

    /// A double tap from the detector. Dropped when a key or click came near it: typing and
    /// clicking shake the palm rest too.
    private func accept(firstKnock first: Double) {
        guard sensor != nil else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        let lastInput = now - TapInputGuard.lastInputAge()
        guard !TapInputGuard.touched(lastInput: lastInput, firstKnock: first) else {
            Log.tap.info("Double tap ignored: typing, a click or the trackpad came \(String(format: "%.2f", lastInput - first), privacy: .public) s from it")
            return
        }
        Log.tap.info("Double tap on the palm rest")
        onTap()
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let rules: [(NotificationCenter, Notification.Name, (inout ChassisTapPower) -> Void)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, { $0.displayAsleep = true }),
            (workspace, NSWorkspace.screensDidWakeNotification, { $0.displayAsleep = false }),
            (workspace, NSWorkspace.willSleepNotification, { $0.systemAsleep = true }),
            (workspace, NSWorkspace.didWakeNotification, { $0.systemAsleep = false }),
            (distributed, Notification.Name("com.apple.screenIsLocked"), { $0.screenLocked = true }),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), { $0.screenLocked = false }),
        ]
        for (center, name, change) in rules {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(change) }
            }
            observers.append((center, token))
        }
        // Battery: once a minute is plenty for a 10% floor.
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readBattery() }
        }
    }

    private func readBattery() {
        let reading = Self.battery()
        update {
            $0.batteryPercent = reading.percent
            $0.onBattery = reading.onBattery
        }
    }

    private static func battery() -> (percent: Int?, onBattery: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, false) }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (current * 100 / maximum, onBattery)
        }
        return (nil, false)
    }
}

/// The sensor-thread half: the detector and the sample rate, so each report costs a few
/// multiply-adds. Confined to the sensor's thread.
///
/// 800 Hz costs about 2% of a core on an M2 (measured by `make verify-tap-cpu`), so the sensor
/// idles at 100 Hz and runs at 800 Hz only for 2 s after the palm rest stirs. The first knock of
/// a double is caught at 100 Hz; by the second the sensor is at full rate.
final class TapPipeline: @unchecked Sendable {
    static let activeHold = 2.0

    private var detector = TapDetector()
    private var rate = SPUAccelerometer.Rate.idle
    private let setRate: @Sendable (SPUAccelerometer.Rate) -> Void
    private let onDoubleTap: @Sendable (Double) -> Void

    init(setRate: @escaping @Sendable (SPUAccelerometer.Rate) -> Void, onDoubleTap: @escaping @Sendable (Double) -> Void) {
        self.setRate = setRate
        self.onDoubleTap = onDoubleTap
    }

    func process(t: Double, _ a: SIMD3<Float>) {
        if case let .doubleTap(first, _)? = detector.process(t: t, a) { onDoubleTap(first) }
        let wanted: SPUAccelerometer.Rate = t - detector.lastStir < Self.activeHold ? .active : .idle
        if wanted != rate {
            rate = wanted
            setRate(wanted)
        }
    }
}
