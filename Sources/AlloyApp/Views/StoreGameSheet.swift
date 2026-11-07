import SwiftUI
import AlloyCore

/// Installs a game through Steam or Epic from its store link: the store app opens at the game and does the rest.
struct StoreGameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let link = StoreGameLink.parse(text)
        let stores = model.gameInstallStores
        VStack(alignment: .leading, spacing: 16) {
            Text("Install from Steam or Epic").font(.title2.bold())
            if stores.isEmpty {
                Text("Install Steam or the Epic Games Launcher first, from Setup. Alloy sets each one up in its own environment, and games you install through it appear here.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Open Setup") { dismiss(); model.selection = .setup }.primaryAction(Theme.accent)
                }
            } else {
                Text("Paste the game's store page link or its Steam app ID. \(stores.map(\.displayName).joined(separator: " or ")) opens at the game: choose Install there. The store checks that you own it and downloads it; Alloy shows the progress and adds the game to your library when it's done.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("store.steampowered.com/app/… or store.epicgames.com/p/…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let link, stores.contains(link.store) { install(link) } }
                Group {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(verbatim: "Examples: store.steampowered.com/app/620/Portal_2/, 620, store.epicgames.com/p/fortnite")
                            .foregroundStyle(.secondary)
                    } else if let link {
                        if stores.contains(link.store) {
                            Label { Text(link.summary) } icon: { Icon("checkmark.circle.fill") }.foregroundStyle(Theme.accentAlt)
                        } else {
                            Label { Text("\(link.summary). Install \(link.store.displayName) from Setup first.") } icon: { Icon("exclamationmark.triangle") }
                                .foregroundStyle(Theme.warning)
                        }
                    } else {
                        Label { Text("Not a Steam or Epic Games Store link.") } icon: { Icon("questionmark.circle") }.foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                    Button(link.map { "Install with \($0.store == .epic ? "Epic" : "Steam")" } ?? "Install") {
                        if let link { install(link) }
                    }
                    .primaryAction(Theme.accent)
                    .disabled(link.map { !stores.contains($0.store) } ?? true)
                }
            }
            if !model.storeDownloads.isEmpty {
                Divider()
                Text("Downloading").font(.headline)
                ForEach(model.storeDownloads) { StoreDownloadRow(download: $0, compact: false) }
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { model.refreshStoreDownloads() }
    }

    func install(_ link: StoreGameLink) {
        model.installThroughStore(link)
        text = ""
    }
}

struct StoreDownloadRow: View {
    let download: StoreDownload
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(compact ? "\(download.store == .epic ? "Epic" : "Steam"): \(download.name)" : download.name).lineLimit(1)
                Spacer()
                Text(status).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(compact ? .callout : .body)
            if let fraction = download.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
    }

    var status: String {
        if download.paused { return "Paused" }
        return download.fraction.map { "\(Int($0 * 100))%" } ?? "Installing"
    }
}
