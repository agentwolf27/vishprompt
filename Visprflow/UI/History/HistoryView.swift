import AppKit
import SwiftUI

/// Every dictation, with what you said, exactly what was sent or that nothing was, and what
/// came out. The privacy ledger: the claim "you can see what left this Mac" made visible.
struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var loadError: String?

    var body: some View {
        NavigationSplitView {
            List(entries, selection: $selection) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(HistoryFormat.title(entry.record))
                        .lineLimit(1)
                    Text("\(entry.record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.record.destination) · \(HistoryFormat.status(entry.record.status))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(entry.id)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay {
                if entries.isEmpty {
                    Text(loadError ?? (search.isEmpty ? "Nothing yet. Hold your key and say something." : "No dictation matches “\(search)”."))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) {
                HistoryDetail(entry: entry)
            } else {
                Text("Choose a dictation to see what was said, what was sent, and what came out.")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Search what you said or what came out")
        .frame(minWidth: 820, minHeight: 520)
        .onAppear(perform: load)
        .onChange(of: search) { load() }
        .toolbar {
            Button("Reload", systemImage: "arrow.clockwise", action: load)
        }
    }

    private func load() {
        guard let queue = Database.queue else {
            loadError = "History is not open yet."
            return
        }
        do {
            entries = try HistoryStore.recent(in: queue, matching: search)
            loadError = nil
            if selection == nil || !entries.contains(where: { $0.id == selection }) {
                selection = entries.first?.id
            }
        } catch {
            loadError = "History could not be read. Reopen the window to try again."
            Log.db.error("History read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct HistoryDetail: View {
    let entry: HistoryEntry
    private var record: DictationRecord { entry.record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(record.destination).font(.title3.weight(.semibold))
                    Text(HistoryFormat.status(record.status))
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                        .foregroundStyle(.secondary)
                }

                block("You said", text: record.rawTranscript.isEmpty ? "(nothing)" : record.rawTranscript, copy: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What left this Mac").font(.headline)
                    Label(HistoryFormat.sentLine(record), systemImage: record.provider == "local" ? "lock.fill" : "arrow.up.right")
                        .foregroundStyle(record.provider == "local" ? .green : .primary)
                    if let model = HistoryFormat.model(record) {
                        Text("Model: \(model)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = HistoryFormat.sentMessage(record) {
                        Text(message)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                if let result = record.compiledText, !result.isEmpty {
                    block("What came out", text: result, copy: true)
                }

                if !entry.timings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Timings").font(.headline)
                            if let total = HistoryFormat.total(entry.timings) {
                                Text("key-up to done: \(total)").foregroundStyle(.secondary)
                            }
                        }
                        ForEach(entry.timings, id: \.stage) { timing in
                            HStack {
                                Text(timing.stage).font(.callout.monospaced())
                                Spacer()
                                Text("+\(HistoryFormat.duration(ms: timing.sinceLastMs))")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("One dictation, one measurement.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func block(_ title: String, text: String, copy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if copy {
                    Button("Copy") { TextRescue.copy(text) }
                }
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
