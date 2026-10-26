import SwiftUI

/// The Palm rest card: the switch, what each tap does, how firm a tap must be, a Test area that
/// shows the gesture it heard without running anything, and left/right calibration.
struct PalmRestCard: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary

    private var ready: Bool { library.palmRestAvailable && library.palmRestEnabled }

    var body: some View {
        SettingsCard(title: "Palm rest") {
            SettingsRow {
                RowText(title: "Tap the palm rest to start",
                        note: library.palmRestAvailable
                            ? "Uses the Mac's motion sensor, never the mic. Pauses when the screen locks or the battery is under 10%."
                            : "This Mac has no palm-rest sensor. It needs an M2 or later MacBook.")
            } trailing: {
                Toggle("Tap the palm rest to start", isOn: $library.palmRestEnabled)
                    .toggleStyle(.switch)
                    .tint(theme.accent.color)
                    .labelsHidden()
                    .disabled(!library.palmRestAvailable)
            }

            if library.palmRestAvailable {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(library.visiblePalmGestures, id: \.self) { gesture in
                            SettingsRow {
                                RowText(title: gesture.title, note: gesture.note)
                            } trailing: {
                                ActionPicker(gesture: gesture, library: library)
                            }
                        }
                        sensitivity
                        SettingsRow {
                            RowText(title: "Play a sound when a tap starts",
                                    note: "So a start you didn't mean is noticed. A tap-started session also waits in the preview card, drops itself if it hears nothing in 3 s, and ends after a minute without new words.")
                        } trailing: {
                            Toggle("Play a sound when a tap starts", isOn: $library.tapStartSound)
                                .toggleStyle(.switch)
                                .tint(theme.accent.color)
                                .labelsHidden()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 16) {
                        testArea
                        calibration
                    }
                    .frame(width: 340)
                }
                .disabled(!ready)
                .opacity(ready ? 1 : 0.55)
                if !library.palmRestEnabled {
                    Text("Turn it on to choose what each tap does.")
                        .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                }
            }
        }
    }

    private var sensitivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            RowText(title: "How firm a tap", note: library.palmSensitivity.note)
            ChoiceRow(options: PalmSensitivity.allCases, selection: $library.palmSensitivity, title: \.title)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { theme.line.color.frame(height: 1) }
    }

    private var testArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it").font(.system(size: 14, weight: .medium))
            if library.palmTesting {
                Text("Tap the palm rest. Nothing starts while this is open.")
                    .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
                HeardLine(result: library.palmHeard)
                Button("Done") { library.stopPalmTest() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent.color)
            } else {
                Text("See which gesture the Mac hears, without starting anything.")
                    .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
                ActionButton(title: "Try a tap", prominent: true) { library.startPalmTest() }
                    .disabled(library.calibrationRun != nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.sunk.color))
    }

    private var calibration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Left and right").font(.system(size: 14, weight: .medium))
            if let run = library.calibrationRun {
                Text(run.instruction)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(run.left.count + run.right.count), total: Double(SideCalibration.tapsPerSide * 2))
                    .tint(theme.accent.color)
                Button("Cancel") { library.cancelCalibration() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent.color)
            } else {
                Text(library.calibrationNote ?? library.palmCalibrationStatus)
                    .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
                ActionButton(title: library.sideCalibration == nil ? "Calibrate left and right…" : "Recalibrate…", prominent: false) {
                    library.startCalibration()
                }
                .disabled(library.palmTesting)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.sunk.color))
    }
}

/// The last thing the Test area heard, lit in the accent while it is fresh.
private struct HeardLine: View {
    @Environment(\.homeTheme) private var theme
    let result: PalmTestResult?

    var body: some View {
        Group {
            if case let .heard(gesture)? = result {
                Text("Heard: \(gesture.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.accent.color))
            } else if let result {
                Text(result.text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink.color)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.accent.color))
            } else {
                Text("Listening…")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.muted.color)
                    .padding(.vertical, 8)
            }
        }
        .frame(minHeight: 36, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(result?.text ?? "Listening")
    }
}

private struct ActionPicker: View {
    @Environment(\.homeTheme) private var theme
    let gesture: PalmGesture
    let library: HomeLibrary

    var body: some View {
        Picker(gesture.title, selection: Binding(
            get: { library.palmAction(for: gesture) },
            set: { library.setPalmAction($0, for: gesture) }
        )) {
            ForEach(PalmAction.allCases, id: \.self) { action in
                Text(action.title).tag(action)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(theme.accent.color)
        .frame(width: 220)
    }
}

private struct ActionButton: View {
    @Environment(\.homeTheme) private var theme
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(prominent ? .white : theme.ink.color)
                .background(RoundedRectangle(cornerRadius: 9).fill(prominent ? theme.accent.color : theme.card.color))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(prominent ? .clear : theme.line.color))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
