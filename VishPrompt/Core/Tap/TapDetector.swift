// Turns the palm-rest accelerometer's stream into double taps.
//
// The approach follows mohammaddanyal/dott-tap's KnockDetector (MIT, credited in NOTICE): a
// ~13 Hz high-pass, an adaptive noise floor, an echo guard after each knock, and rejecting a long
// ring or a change in gravity as handling. This file is written here, not copied, and is pure:
// no IOKit, no clock, so recorded samples drive it in tests exactly as the sensor does.

import Foundation
import simd

/// What the detector concluded, and when.
enum TapEvent: Equatable, Sendable {
    /// Two knocks close together, with no key press, click or handling around them. `first` is
    /// the first knock and `at` the second, on the sensor's clock.
    case doubleTap(first: Double, at: Double)
}

struct TapDetector: Sendable {
    struct Tuning: Equatable, Sendable {
        /// A knock must be this many times the background noise…
        var noiseMultiple: Float = 6
        /// …and at least this strong, in g. The right side of the palm rest reads as low as 7 mg.
        var minimumPeak: Float = 0.006
        /// Harder than this is a slap or a drop.
        var maximumPeak: Float = 2.5
        /// A knock rings for 30–150 ms. Longer means the Mac is being moved or shaken.
        var maximumRing: Double = 0.22
        /// A change in the direction of gravity, in g, means the Mac was lifted or tilted.
        var maximumTilt: Float = 0.05
        /// Knocks this soon after handling are ignored: setting a Mac down rattles.
        var handlingQuiet: Double = 0.8
        /// The second knock of a double comes this soon after the first, and no sooner.
        var doubleWindow: ClosedRange<Double> = 0.08...0.45
        /// No third knock may follow this soon after the second: a burst is not a gesture.
        var burstGuard: Double = 0.25
        /// A key press or click this close to a knock (before it, or just after it, since the
        /// event can be reported a little late) means the knock was typing or clicking.
        var inputBefore: Double = 0.4
        var inputAfter: Double = 0.15
    }

    let tuning: Tuning

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    // Filter state.
    private var lastT: Double?
    private var previous = SIMD3<Float>.zero
    private var highPass = SIMD3<Float>.zero
    private var lowPass = SIMD3<Float>.zero
    private var gravity = SIMD3<Float>(0, 0, -1)
    private var noise: Float = 0.002
    private var warmup = 0

    // The knock being measured.
    private var capturing = false
    private var captureStart = 0.0
    private var captureThreshold: Float = 0
    private var peak: Float = 0
    private var peakT = 0.0
    private var lastLoud = 0.0
    private var gravityBefore = SIMD3<Float>.zero
    private var lastOnset = -10.0

    // After a knock its ring raises the bar for a moment, so the tail is never a second knock.
    private var echoPeak: Float = 0
    private var echoT = -10.0
    private var lastHandling = -10.0

    // Accepted knocks waiting to become (or not become) a double tap, and recent input.
    private var knocks: [Double] = []
    private var inputs: [Double] = []

    /// The last time something knock-sized moved the palm rest. The sensor runs slowly until
    /// then and fast for a moment after, which is most of what keeps it cheap. Anything lower
    /// would be woken by the Mac's own resting noise.
    private(set) var lastStir = -10.0

    /// Where the detector is, for the overlay's tests and for logging.
    private(set) var rejected: [(at: Double, reason: String)] = []

    /// A key press or click at time `t`, on the sensor's clock.
    mutating func noteInput(at t: Double) {
        inputs.append(t)
        if inputs.count > 32 { inputs.removeFirst(inputs.count - 32) }
    }

    /// Feeds one sample (seconds, g). Returns a double tap once it is certain: after the burst
    /// guard has passed with no third knock.
    mutating func process(t: Double, _ a: SIMD3<Float>) -> TapEvent? {
        guard let last = lastT, t > last, t - last < 0.1 else {
            // First sample, or the stream paused or changed rate: restart around here.
            lastT = t
            previous = a
            highPass = .zero
            lowPass = a
            if warmup == 0 { gravity = a }
            capturing = false
            warmup = 1
            return nil
        }
        let dt = Float(min(t - last, 0.02))
        lastT = t

        // ~13 Hz one-pole high-pass keeps the knock and drops posture and slow motion.
        let alpha: Float = 0.012 / (0.012 + dt)
        highPass = alpha * (highPass + a - previous)
        previous = a
        // ~30 ms low-pass, for the tilt check.
        lowPass += (dt / (0.03 + dt)) * (a - lowPass)
        let m = simd_length(highPass)

        if warmup < 80 {
            warmup += 1
            gravity += min(1, dt / 0.15) * (a - gravity)
            noise += (dt / 0.5) * (m - noise)
            return nil
        }

        if capturing {
            lastStir = t
            if m > peak { peak = m; peakT = t }
            if m > max(peak * 0.15, captureThreshold * 0.5) { lastLoud = t }
            let elapsed = t - captureStart
            if elapsed >= tuning.maximumRing {
                finishKnock(at: t, ringing: m > peak * 0.25)
            } else if elapsed >= 0.04, t - lastLoud >= 0.02 {
                finishKnock(at: t, ringing: false)
            }
            return decide(at: t)
        }

        // Quiet: follow gravity and the noise floor. The floor rises slowly and falls faster, so
        // one bump doesn't deafen the detector for seconds.
        gravity += (dt / 0.6) * (a - gravity)
        noise += (m > noise ? dt / 4 : dt / 1.5) * (m - noise)
        noise = max(noise, 0.0003)

        var threshold = max(tuning.minimumPeak, tuning.noiseMultiple * noise)
        let sinceEcho = Float(t - echoT)
        if sinceEcho < 0.6 { threshold = max(threshold, echoPeak * 0.6 * exp(-sinceEcho / 0.1)) }
        if m > threshold, t - lastOnset > 0.06 {
            capturing = true
            captureStart = t
            captureThreshold = threshold
            peak = m
            peakT = t
            lastLoud = t
            lastOnset = t
            gravityBefore = gravity
        }
        return decide(at: t)
    }

    // MARK: Private

    private mutating func finishKnock(at t: Double, ringing: Bool) {
        capturing = false
        echoPeak = peak
        echoT = t
        let tilt = simd_length(lowPass - gravityBefore)
        let reason: String?
        if ringing {
            reason = "rang too long"
        } else if tilt > tuning.maximumTilt {
            reason = "the Mac moved"
        } else if captureStart - lastHandling < tuning.handlingQuiet {
            reason = "right after handling"
        } else if peak > tuning.maximumPeak {
            reason = "too hard"
        } else {
            reason = nil
        }
        if let reason {
            if reason != "too hard" { lastHandling = t }
            reject(captureStart, reason)
            // Handling spoils any half-made double around it.
            knocks.removeAll()
            return
        }
        knocks.append(captureStart)
    }

    /// Turns accepted knocks into a double tap once nothing can still spoil it.
    private mutating func decide(at t: Double) -> TapEvent? {
        guard let first = knocks.first else { return nil }
        if knocks.count == 1 {
            // A single knock that waited out the window is not half of anything.
            if t - first > tuning.doubleWindow.upperBound { knocks.removeAll() }
            return nil
        }
        let second = knocks[1]
        if knocks.count >= 3 {
            reject(first, "a burst of knocks")
            knocks.removeAll()
            return nil
        }
        guard tuning.doubleWindow.contains(second - first) else {
            // Too far apart for a double: the second may still start one.
            knocks.removeFirst()
            return nil
        }
        guard t - second >= max(tuning.burstGuard, tuning.inputAfter), !capturing else { return nil }
        knocks.removeAll()
        let touched = inputs.contains { input in
            [first, second].contains { knock in input >= knock - tuning.inputBefore && input <= knock + tuning.inputAfter }
        }
        if touched {
            reject(first, "typing or clicking")
            return nil
        }
        return .doubleTap(first: first, at: second)
    }

    private mutating func reject(_ t: Double, _ reason: String) {
        rejected.append((t, reason))
        if rejected.count > 64 { rejected.removeFirst(rejected.count - 64) }
    }
}
