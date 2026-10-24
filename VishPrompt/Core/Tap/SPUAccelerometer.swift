// The palm-rest motion sensor of Apple Silicon MacBooks, read for the chassis tap trigger.
//
// The device is undocumented. What is known about it comes from MIT-licensed work, credited in
// NOTICE: yu2001-s/TapTap (Sources/TapCore/SPUSensor.swift) and mohammaddanyal/dott-tap
// (Sources/DottTap/Sensor/AccelSensor.swift). This file is written here, not copied.

import Foundation
import IOKit
import IOKit.hid
import os

/// One accelerometer report, decoded.
///
/// Reports are 22 bytes; x, y and z are little-endian Int32 at offsets 6, 10 and 14, in
/// 1/65536 g. Anything else is not an accelerometer report and is dropped.
enum AccelReport {
    static let length = 22

    static func parse(_ bytes: UnsafeRawBufferPointer) -> SIMD3<Float>? {
        guard bytes.count == length else { return nil }
        func axis(_ offset: Int) -> Float {
            Float(Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self))) / 65536
        }
        return SIMD3(axis(6), axis(10), axis(14))
    }
}

enum AccelerometerError: Error, Equatable {
    /// This Mac has no such sensor: an M1 MacBook Air, a desktop, an Intel Mac.
    case unavailable
    /// The sensor is there but would not open.
    case openFailed(code: Int32)
}

/// Reads the accelerometer behind `AppleSPUHIDDevice` (vendor page 0xFF00, usage 3).
///
/// Opening the device needs no permission (checked on macOS 15.2 by a hardened app with no
/// grants; PROGRESS.md, 2026-10-23). Opened alone it sends nothing: its driver must be told to
/// report, to power on and how often, by writing three properties (DECISIONS.md D2). Reports
/// arrive on a private thread, so the main thread never wakes for them.
final class SPUAccelerometer: @unchecked Sendable {
    enum Rate: Int, Sendable {
        /// Enough to notice that something touched the Mac, at an eighth of the work.
        case idle = 100
        /// Enough to tell a tap's shape.
        case active = 800

        var intervalMicroseconds: Int { 1_000_000 / rawValue }
    }

    /// Seconds (on the mach clock) and acceleration in g, on the sensor thread. Keep it cheap.
    var onSample: (@Sendable (Double, SIMD3<Float>) -> Void)?

    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var rate: Rate = .idle
    private var samplesSinceCheck = 0
    private var watchdog: DispatchSourceTimer?
    /// The accelerometer's driver, found once: the watchdog corrects its rate about once a
    /// second, and searching the registry each time would cost more than the correction.
    private var driver: io_service_t = 0
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static var isAvailable: Bool {
        guard let service = service(className: "AppleSPUHIDDevice", usage: 3, reportSize: AccelReport.length) else { return false }
        IOObjectRelease(service)
        return true
    }

    var isRunning: Bool {
        lock.withLock { device != nil }
    }

    deinit {
        stop()
        buffer.deallocate()
    }

    func start(rate: Rate) throws {
        guard !isRunning else { return setRate(rate) }
        guard let service = Self.service(className: "AppleSPUHIDDevice", usage: 3, reportSize: AccelReport.length) else {
            throw AccelerometerError.unavailable
        }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw AccelerometerError.unavailable }
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw AccelerometerError.openFailed(code: status) }

        lock.withLock {
            self.device = device
            self.rate = rate
            self.samplesSinceCheck = 0
        }
        applyRate(rate, wake: true)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, buffer, 64, { context, _, _, _, _, report, length, timeStamp in
            guard let context, let sample = AccelReport.parse(UnsafeRawBufferPointer(start: report, count: length)) else { return }
            Unmanaged<SPUAccelerometer>.fromOpaque(context).takeUnretainedValue().deliver(timeStamp: timeStamp, sample)
        }, context)

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let loop = CFRunLoopGetCurrent() else { ready.signal(); return }
            self.lock.withLock { self.runLoop = loop }
            IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "VishPrompt.accelerometer"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
        ready.wait()
        // Scheduling the device resets its driver to the default 800 Hz, so the rate set above
        // only takes once it is set again here (measured: 100 Hz asked before this, 796 given).
        applyRate(rate)

        // macOS parks the sensor when the Mac sits still, and the driver can drift back to its
        // default rate. Re-arm it only when the rate is off by more than half or double:
        // writing it unconditionally costs more.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + Self.checkInterval, repeating: Self.checkInterval, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.checkRate() }
        timer.resume()
        lock.withLock { watchdog = timer }
        Log.tap.info("Accelerometer started at \(rate.rawValue, privacy: .public) Hz")
    }

    func setRate(_ new: Rate) {
        let changed = lock.withLock {
            guard device != nil, rate != new else { return false }
            rate = new
            samplesSinceCheck = 0
            return true
        }
        if changed { applyRate(new) }
    }

    func stop() {
        let (device, loop, timer) = lock.withLock {
            let parts = (self.device, runLoop, watchdog)
            self.device = nil
            runLoop = nil
            watchdog = nil
            return parts
        }
        timer?.cancel()
        guard let device else { return }
        if let loop {
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(loop)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        lock.withLock {
            if driver != 0 { IOObjectRelease(driver) }
            driver = 0
        }
        thread = nil
        Log.tap.info("Accelerometer stopped")
    }

    // MARK: Private

    private func deliver(timeStamp: UInt64, _ sample: SIMD3<Float>) {
        lock.withLock { samplesSinceCheck += 1 }
        onSample?(Double(timeStamp) * secondsPerTick, sample)
    }

    /// How often the delivered rate is checked. Short, because something in macOS (the HID event
    /// system is a client of the same driver) puts it back to 800 Hz about a second after it is
    /// set to 100, and every moment at 800 Hz costs CPU. Measured on macOS 15.2: idle averages
    /// 150–260 Hz this way, against 800 if left alone. Setting the rate through the event system
    /// instead is refused: the service is motion-restricted.
    static let checkInterval = 0.1

    private func checkRate() {
        let (count, rate) = lock.withLock {
            defer { samplesSinceCheck = 0 }
            return (samplesSinceCheck, self.rate)
        }
        // Too slow: macOS parked the sensor. Too fast: macOS put the driver back to 800 Hz.
        let expected = Double(rate.rawValue) * Self.checkInterval
        if Double(count) < expected / 2 {
            applyRate(rate, wake: true)
        } else if Double(count) > expected * 2 {
            applyRate(rate)
        }
    }

    /// Tells the accelerometer's driver to report, powered, at `rate`. Only that driver is
    /// touched; the same sensor hub also serves the lid angle, ambient light and others. On
    /// macOS 15.2 the drivers carry no `Product` name, so it is matched by usage 3.
    private func applyRate(_ rate: Rate, wake: Bool = false) {
        let driver = lock.withLock {
            if self.driver == 0 {
                self.driver = Self.service(className: "AppleSPUHIDDriver", usage: 3, reportSize: nil) ?? 0
            }
            return self.driver
        }
        guard driver != 0 else { return }
        Self.configureDriver(driver, rate: rate, wake: wake)
    }

    private static func configureDriver(_ driver: io_service_t, rate: Rate, wake: Bool) {
        if wake {
            IORegistryEntrySetCFProperty(driver, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(driver, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
        }
        IORegistryEntrySetCFProperty(driver, "ReportInterval" as CFString, rate.intervalMicroseconds as CFNumber)
    }

    private static func service(className: String, usage: Int, reportSize: Int?) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            if int(service, "PrimaryUsagePage") == 0xFF00, int(service, "PrimaryUsage") == usage,
               reportSize == nil || int(service, "MaxInputReportSize") == reportSize {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private static func int(_ service: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
}
