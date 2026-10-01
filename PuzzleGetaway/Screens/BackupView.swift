import SwiftUI
import UniformTypeIdentifiers

/// Offline progress and backup: save status, export to a `.pgsave` file, import with confirmation.
struct BackupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    @State private var exportDocument: SaveDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: SaveData?
    @State private var confirmImport = false
    @State private var message: String?

    private var save: SaveData { model.save }

    private var lastSavedText: String {
        guard let date = model.lastSaveDate else { return "Just now" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private var defaultFilename: String {
        "PuzzleGetaway-\(Progression.dateKey(Date()))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                statusCard
                explanationCard
                actions
                if let message = message {
                    Text(message)
                        .font(Theme.font(.subheadline, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                        .accessibilityIdentifier("backupMessage")
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Progress and backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .pgsave,
                      defaultFilename: defaultFilename) { result in
            switch result {
            case .success: message = "Your progress file was saved."
            case .failure: message = "That didn't work this time. Nothing was changed."
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pgsave, .json, .data]) { result in
            handleImport(result)
        }
        .confirmationDialog("Replace your progress?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Replace progress", role: .destructive) {
                if let incoming = pendingImport {
                    model.replaceSave(incoming)
                    message = "Progress loaded from the file."
                }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text(importSummary)
        }
    }

    // MARK: Pieces

    private var statusCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Saved on this device", systemImage: "checkmark.circle.fill")
                    .font(Theme.font(.headline, weight: .bold))
                    .foregroundColor(theme.success)
                    .accessibilityIdentifier("savedStatus")
                Text("Last saved: \(lastSavedText)")
                    .font(Theme.body)
                    .foregroundColor(theme.textPrimary)
                Text("\(save.progress.count) \(save.progress.count == 1 ? "puzzle" : "puzzles") solved · \(save.totalStars) \(save.totalStars == 1 ? "star" : "stars")")
                    .font(Theme.caption)
                    .foregroundColor(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var explanationCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("No internet needed", systemImage: "wifi.slash")
                    .font(Theme.font(.headline, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("Your progress lives on this device and saves itself as you play. To move to a new device or keep a safety copy, export a progress file and import it where you want it.")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                do {
                    exportDocument = SaveDocument(data: try model.saveStore.exportData(model.save))
                    showExporter = true
                } catch {
                    message = "We couldn't prepare the file. Your progress is still safe."
                }
            } label: {
                Label("Export progress", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("exportProgress")

            Button {
                showImporter = true
            } label: {
                Label("Import progress", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("importProgress")
        }
    }

    // MARK: Import

    private var importSummary: String {
        guard let incoming = pendingImport else { return "" }
        let n = incoming.progress.count
        return "This file has \(n) \(n == 1 ? "puzzle" : "puzzles") solved and \(incoming.totalStars) stars. It will replace the progress on this device."
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            message = "We couldn't open that file. Nothing was changed."
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                message = "We couldn't read that file. Nothing was changed."
                return
            }
            do {
                pendingImport = try SaveStore.validateImport(data)
                confirmImport = true
            } catch SaveError.unsupportedVersion(_) {
                message = "That file is from a newer version of the game. Please update and try again."
            } catch {
                message = "That doesn't look like a Puzzle Getaway progress file. Nothing was changed."
            }
        }
    }
}
