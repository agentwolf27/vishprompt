import Foundation

/// Whether this Mac can tell left palm-rest taps from right ones, measured, never assumed.
///
/// The person taps left ten times and right ten times. Each tap's shape (`KnockShape`) is
/// classified by the nearest side centre, computed without that tap (leave one out). The side
/// rows unlock only at 95% or better: 19 of 20. Five a side was the plan, but on Vish's first bed
/// session, whose sides are at chance over every knock (64%), its first five a side happened to
/// score 100%: five is too few to trust. Decided per run, never by the kind of Mac.
struct SideCalibration: Codable, Equatable, Sendable {
    static let required = 0.95
    static let tapsPerSide = 10
    static let key = "palmSideCalibration"

    var left: [Float]
    var right: [Float]
    /// Leave-one-out accuracy on the calibration taps.
    var accuracy: Double
    var taps: Int
    var date: Date
    /// The Mac it was measured on, so preferences copied to another Mac do not carry it over.
    var model: String

    var unlocked: Bool { accuracy >= Self.required }

    /// Measures a calibration run. Nil when there are too few taps on either side to judge.
    static func measure(left: [KnockShape], right: [KnockShape], model: String = SideCalibration.hardwareModel, date: Date = Date()) -> SideCalibration? {
        guard left.count >= 3, right.count >= 3 else { return nil }
        let samples = left.map { ($0.vector, true) } + right.map { ($0.vector, false) }
        var correct = 0
        for (index, sample) in samples.enumerated() {
            let rest = samples.enumerated().filter { $0.offset != index }.map(\.element)
            let leftCentre = centre(rest.filter(\.1).map(\.0))
            let rightCentre = centre(rest.filter { !$0.1 }.map(\.0))
            let saysLeft = distance(sample.0, leftCentre) < distance(sample.0, rightCentre)
            if saysLeft == sample.1 { correct += 1 }
        }
        return SideCalibration(left: centre(left.map(\.vector)), right: centre(right.map(\.vector)),
                               accuracy: Double(correct) / Double(samples.count), taps: samples.count, date: date, model: model)
    }

    enum Side: String, Sendable { case left, right }

    /// The side of a gesture, or nil when its knocks disagree or sit too near the middle. Never
    /// a guess: a gesture that cannot be placed does not run a side's action.
    func side(of shapes: [KnockShape]) -> Side? {
        guard unlocked, !shapes.isEmpty else { return nil }
        let calls: [Side?] = shapes.map { shape in
            let toLeft = Self.distance(shape.vector, left)
            let toRight = Self.distance(shape.vector, right)
            // Clearly nearer one centre: at most 70% of the distance to the other.
            if toLeft < 0.7 * toRight { return .left }
            if toRight < 0.7 * toLeft { return .right }
            return nil
        }
        guard let first = calls.first, let side = first, calls.allSatisfy({ $0 == side }) else { return nil }
        return side
    }

    // MARK: Storage, per Mac

    static func saved(in defaults: UserDefaults = .standard, model: String = SideCalibration.hardwareModel) -> SideCalibration? {
        guard let data = defaults.data(forKey: key),
              let calibration = try? JSONDecoder().decode(SideCalibration.self, from: data),
              calibration.model == model
        else { return nil }
        return calibration
    }

    func save(in defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func forget(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Why the side rows stay locked, for the Palm rest card.
    static let lockedReason = "This Mac can't tell your left and right taps apart on this surface; try calibrating at a desk."

    static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: Maths

    private static func centre(_ vectors: [[Float]]) -> [Float] {
        guard let width = vectors.first?.count else { return [] }
        return (0..<width).map { i in vectors.map { $0[i] }.reduce(0, +) / Float(vectors.count) }
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }
}
