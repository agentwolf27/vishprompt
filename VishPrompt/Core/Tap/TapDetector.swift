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
        var maximumTilt: Float = 0.08
        /// Knocks this soon after handling are ignored: setting a Mac down rattles.
        var handlingQuiet: Double = 1.5
        /// The second knock of a double comes this soon after the first, and no sooner.
        var doubleWindow: ClosedRange<Double> = 0.08...0.45
        /// The second knock must be a new hit, at least this share of the first's peak. A bounce
        /// in a bump's ring is weaker; a real second tap is about as firm as the first.
        var secondShare: Float = 0.4
        /// The first tap of a double starts from stillness: the shaking just before it is under
        /// this share of its peak (desk taps: about 2%; a wobble in a long settle: about half).
        var quietLead: Float = 0.3
        /// How far the ~300 ms posture may drift from the ~600 ms gravity, while no knock rings,
        /// before the Mac counts as being moved.
        var postureDrift: Float = 0.03
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
    /// The quietest the ring has been since its peak, to spot a second tap landing inside it.
    private var trough: Float = 0

    // After a knock its ring raises the bar for a moment, so the tail is never a second knock.
    private var echoPeak: Float = 0
    private var echoT = -10.0
    private var lastHandling = -10.0

    // Accepted knocks waiting to become (or not become) a double tap, and recent input.
    private var knocks: [(t: Double, peak: Float, before: SIMD3<Float>, lead: Float)] = []
    /// The shaking just before now (~30 ms average of the high-passed magnitude). A tap starts
    /// from stillness; a wobble in a long settle starts from shaking.
    private var level: Float = 0
    private var leadIn: Float = 0
    /// The Mac's posture: acceleration averaged over ~300 ms, slow enough that a tap's own swing
    /// averages out, fast enough to see a lift. A firm tap moves the chassis for a moment
    /// without changing how it sits; lifting or tilting it does (desk recordings, 2026-10-25).
    private var posture = SIMD3<Float>(0, 0, -1)
    private var inputs: [Double] = []

    /// The last time something knock-sized moved the palm rest. The sensor runs slowly until
    /// then and fast for a moment after, which is most of what keeps it cheap. Anything lower
    /// would be woken by the Mac's own resting noise.
    private(set) var lastStir = -10.0

    /// Knocks accepted as taps (time, peak in g), for tests and the Test area to come.
    private(set) var heard: [(at: Double, peak: Float)] = []

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
            posture = a
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
        // ~30 ms low-pass, and the slower posture, for the tilt check.
        lowPass += (dt / (0.03 + dt)) * (a - lowPass)
        posture += (dt / (0.3 + dt)) * (a - posture)
        let m = simd_length(highPass)
        let levelBefore = level
        level += (dt / (0.03 + dt)) * (m - level)

        if warmup < 80 {
            warmup += 1
            gravity += min(1, dt / 0.15) * (a - gravity)
            noise += (dt / 0.5) * (m - noise)
            return nil
        }

        if capturing {
            lastStir = t
            let elapsed = t - captureStart
            // A second tap often lands while the first still rings (desk recordings: 0.28-0.31 s
            // apart, the first ringing at 20-60% of its peak). A fresh rise to 60% of the peak
            // after the ring dipped below 35% closes the first knock and starts the next.
            if elapsed > 0.08, trough < peak * 0.35, m > peak * 0.6 {
                let threshold = captureThreshold
                finishKnock(at: t, ringing: false)
                beginCapture(at: t, magnitude: m, threshold: threshold, lead: trough)
                return decide(at: t)
            }
            if m > peak { peak = m; peakT = t; trough = m }
            if t - peakT > 0.01 { trough = min(trough, m) }
            if m > max(peak * 0.15, captureThreshold * 0.5) { lastLoud = t }
            if elapsed >= tuning.maximumRing {
                finishKnock(at: t, ringing: m > peak * 0.25)
            } else if elapsed >= 0.04, t - lastLoud >= 0.02 {
                finishKnock(at: t, ringing: false)
            }
            return decide(at: t)
        }

        // Posture drifting away from gravity while no knock is ringing means the Mac is being
        // lifted, tilted or set down: knocks for the next moment are handling, not taps.
        if simd_length(posture - gravity) > tuning.postureDrift { lastHandling = t }

        // Quiet: follow gravity and the noise floor. The floor rises slowly and falls faster, so
        // one bump doesn't deafen the detector for seconds.
        gravity += (dt / 0.6) * (a - gravity)
        noise += (m > noise ? dt / 4 : dt / 1.5) * (m - noise)
        noise = max(noise, 0.0003)

        var threshold = max(tuning.minimumPeak, tuning.noiseMultiple * noise)
        let sinceEcho = Float(t - echoT)
        if sinceEcho < 0.6 { threshold = max(threshold, echoPeak * 0.6 * exp(-sinceEcho / 0.1)) }
        if m > threshold, t - lastOnset > 0.06 {
            beginCapture(at: t, magnitude: m, threshold: threshold, lead: levelBefore)
        }
        return decide(at: t)
    }

    // MARK: Private

    private mutating func beginCapture(at t: Double, magnitude m: Float, threshold: Float, lead: Float) {
        leadIn = lead
        capturing = true
        captureStart = t
        captureThreshold = threshold
        peak = m
        peakT = t
        trough = m
        lastLoud = t
        lastOnset = t
        gravityBefore = gravity
    }

    private mutating func finishKnock(at t: Double, ringing: Bool) {
        capturing = false
        echoPeak = peak
        echoT = t
        let reason: String?
        if ringing {
            reason = "rang too long"
        } else if captureStart - lastHandling < tuning.handlingQuiet {
            reason = "right after handling"
        } else if peak > tuning.maximumPeak {
            reason = "too hard"
        } else {
            reason = nil
        }
        if let reason {
            // Only a change in posture (judged in `decide`) opens the handling window. A long
            // ring or a knock inside the window spoils this double but must not extend it, or
            // one bump keeps the detector deaf for seconds.
            reject(captureStart, reason)
            // Handling spoils any half-made double around it.
            knocks.removeAll()
            return
        }
        knocks.append((captureStart, peak, gravityBefore, leadIn))
        heard.append((captureStart, peak))
        if heard.count > 64 { heard.removeFirst(heard.count - 64) }
    }

    /// Turns accepted knocks into a double tap once nothing can still spoil it.
    private mutating func decide(at t: Double) -> TapEvent? {
        guard let firstKnock = knocks.first else { return nil }
        let first = firstKnock.t
        if knocks.count == 1 {
            // A single knock that waited out the window is not half of anything. Not while a knock
            // is still being measured: it joins the list only when its capture ends, ~0.2 s after
            // it began, and clearing now would throw away the first half of a slow double.
            if t - first > tuning.doubleWindow.upperBound, !capturing { knocks.removeAll() }
            return nil
        }
        let second = knocks[1].t
        if knocks.count == 2, knocks[1].peak < tuning.secondShare * firstKnock.peak {
            // A bounce in the first knock's ring, not a second tap: drop it and keep waiting.
            knocks.removeLast()
            return nil
        }
        if knocks.count == 2, firstKnock.lead > tuning.quietLead * firstKnock.peak {
            reject(first, "began in shaking")
            knocks.removeAll()
            return nil
        }
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
        // Judged now, a quarter second after the second knock, when the taps' swing has
        // averaged out of the posture: did the Mac end up sitting differently?
        let tilt = simd_length(posture - firstKnock.before)
        if tilt > tuning.maximumTilt {
            lastHandling = t
            reject(first, String(format: "the Mac moved %.3f", tilt))
            return nil
        }
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
