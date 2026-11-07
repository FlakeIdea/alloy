import AppKit
import SwiftUI
import AlloyCore

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        if let game = model.game(model.selectedGameID) {
            GameDetailView(game: game)
        } else {
            let stores = model.games.filter(isStoreApp)
            let apps = model.games.filter { $0.isApp && !isStoreApp($0) }
            let games = model.games.filter { !$0.isApp && !isStoreApp($0) }
            Group {
                if !model.hasGameEngine && model.games.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Wordmark().padding(.leading, 36).padding(.top, 22)
                        PageHeader(title: "Your games", subtitle: "Library")
                        WelcomeCard().padding(.horizontal, 36)
                        Spacer()
                    }
                } else if model.games.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Wordmark().padding(.leading, 36).padding(.top, 22)
                        PageHeader(title: "Your games", subtitle: "Library")
                        EmptyShelf()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let featured = spotlight(!games.isEmpty ? games : !stores.isEmpty ? stores : apps) {
                                Spotlight(game: featured)
                            }
                            VStack(alignment: .leading, spacing: 34) {
                                if !model.hasGameEngine { WelcomeCard() }
                                activity
                                if !games.isEmpty {
                                    shelf(title: "All games", count: games.count) {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: 24, alignment: .top)],
                                                  alignment: .leading, spacing: 30) {
                                            ForEach(sorted(games)) { game in
                                                CoverCard(game: game).onTapGesture { model.selectedGameID = game.id }
                                            }
                                        }
                                    }
                                }
                                if !apps.isEmpty {
                                    shelf(title: "Apps", count: apps.count) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 14) {
                                                ForEach(apps) { game in
                                                    StoreTile(game: game).onTapGesture { model.selectedGameID = game.id }
                                                }
                                            }
                                        }
                                    }
                                }
                                if !stores.isEmpty {
                                    shelf(title: "Stores", count: stores.count) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 14) {
                                                ForEach(stores) { game in
                                                    StoreTile(game: game).onTapGesture { model.selectedGameID = game.id }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 36).padding(.top, 8).padding(.bottom, 40)
                        }
                    }
                }
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .overlay(Text("Drop to add this game").font(.system(size: 22, weight: .heavy)))
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.canvas.opacity(0.8)))
                        .padding(16)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: \.isFileURL) else { return false }
                model.handleDrop(url)
                return true
            } isTargeted: { dropTargeted = $0 }
        }
    }

    private func isStoreApp(_ game: Game) -> Bool {
        GameStore.store(for: game) != nil && !StoreLibraryScanner.startsAGame(game)
    }

    /// The game running now, else the last one played, else the newest.
    private func spotlight(_ games: [Game]) -> Game? {
        games.first { model.state(of: $0.id).isRunning }
            ?? games.filter { $0.lastPlayed != nil }.max { $0.lastPlayed! < $1.lastPlayed! }
            ?? games.last
    }

    /// Most recently played first, then by name.
    private func sorted(_ games: [Game]) -> [Game] {
        games.sorted {
            switch ($0.lastPlayed, $1.lastPlayed) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Installs and store downloads in progress.
    @ViewBuilder private var activity: some View {
        if let status = model.setupInstallStatus ?? model.storeInstallStatus.values.first {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
            }
            .padding(14).glassCard()
        } else if let download = model.storeDownloads.first {
            Button { model.sheet = .storeGame } label: { StoreDownloadRow(download: download, compact: true) }
                .buttonStyle(.flat).padding(14).glassCard()
        }
    }

    private func shelf<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                Text(String(format: "%02d", count)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                Rectangle().fill(Theme.hairline).frame(height: 1).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            }
            content()
        }
    }
}

/// No games yet: where they come from.
private struct EmptyShelf: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            way("01", "A game folder", "Already installed on a drive, or copied from your PC. Drag the folder or its .exe here.") {
                model.pendingAdd = AppModel.chooseFolder(prompt: "Add Game")
            }
            way("02", "A store", "Steam, Epic, EA, Ubisoft, GOG or Battle.net. Alloy installs the store, then you download games in it.") {
                model.sheet = .storeGame
            }
            way("03", "A setup file", "An offline installer (setup.exe or .msi). Alloy runs it in a new environment and adds the game.") {
                model.pendingSetup = AppModel.chooseFile(types: ["exe", "msi"], prompt: "Choose Setup")
            }
        }
        .padding(.horizontal, 36).padding(.top, 8)
    }

    private func way(_ number: String, _ title: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(number).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                Text(title).font(.system(size: 17, weight: .bold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                HStack(spacing: 6) { GlyphView(glyph: .add, size: 11); Text("Add") }.font(.system(size: 12, weight: .semibold))
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.flat)
    }
}

struct AddGameMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button {
            popUpMenu([
                MenuChoice(title: "Add Installed Game Folder…") { model.addingApp = false; model.pendingAdd = AppModel.chooseFolder(prompt: "Add Game") },
                MenuChoice(title: "Install from Setup File…", enabled: model.hasGameEngine && model.setupInstallStatus == nil) {
                    model.pendingSetup = AppModel.chooseFile(types: ["exe", "msi"], prompt: "Choose Setup")
                },
                MenuChoice(title: "Install from Steam, Epic or Another Store…") { model.sheet = .storeGame },
                MenuChoice(title: "Add Windows App…", separatorBefore: true) {
                    model.addingApp = true; model.pendingAdd = AppModel.chooseFolder(prompt: "Add App")
                },
            ])
        } label: {
            HStack(spacing: 6) { GlyphView(glyph: .add, size: 11, weight: 2); Text("Add Game") }
        }
        .buttonStyle(PrimaryCapsule())
        .controlSize(.small)
        .fixedSize()
    }
}

/// First start: the one thing to do before adding games.
struct WelcomeCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "First, one download")
                Text("Welcome to Alloy").font(.system(size: 22, weight: .heavy))
                Text("Install the game engine once (one download), then add your Windows games and press Play. Alloy picks the fastest graphics and installs what each game needs.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Setup") { model.selection = .setup }.primaryAction(Theme.accent)
        }
        .padding(22)
        .glassCard(cornerRadius: 24)
    }
}

struct ArtworkView: View {
    let url: URL?
    let name: String
    /// Off where the game's name is already shown large over the artwork.
    var showsInitials = true
    /// Shown instead of initials, for store apps.
    var symbol: String? = nil

    var body: some View {
        ZStack {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: Self.tone(for: name), startPoint: .topLeading, endPoint: .bottomTrailing)
                if showsInitials {
                    if let symbol {
                        Icon(symbol).font(.system(size: 46, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text(initials).font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .clipped()
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Graphite, slate and stone greys, picked from the name so a game keeps its look between launches.
    static let tones: [[Color]] = [
        [Color(white: 0.52), Color(white: 0.08)],
        [Color(white: 0.42), Color(white: 0.06)],
        [Color(red: 0.44, green: 0.47, blue: 0.52), Color(white: 0.07)],
        [Color(white: 0.34), Color(white: 0.04)],
        [Color(red: 0.50, green: 0.48, blue: 0.46), Color(white: 0.07)],
    ]

    static func tone(for name: String) -> [Color] {
        tones[name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % tones.count]
    }
}

struct GameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    var body: some View {
        let store = GameStore.store(for: game)
        let isStoreApp = store != nil && !StoreLibraryScanner.startsAGame(game)
        ArtworkView(url: game.artwork, name: game.name, symbol: isStoreApp ? "bag.fill" : nil)
            .frame(height: 230)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name).font(.headline).lineLimit(1)
                    Text(subtitle(store: store, isStoreApp: isStoreApp))
                        .lineLimit(1).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16)
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if model.state(of: game.id).isRunning {
                    Label { Text("Running") } icon: { Icon("play.fill") }.font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassCard(cornerRadius: 12).padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(hovering ? 0.35 : 0.08), lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.45 : 0.25), radius: hovering ? 18 : 10, y: hovering ? 10 : 6)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.smooth(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }

    func subtitle(store: GameStore?, isStoreApp: Bool) -> String {
        if isStoreApp { return "Game store" }
        let mode = game.graphics.backend.isCompatibilityMode ? "Compatibility mode"
            : PlayMode.current(of: game.graphics)?.displayName ?? "Custom graphics"
        return store.map { "\($0.environmentName) · \(mode)" } ?? mode
    }
}

// MARK: - Add game

struct AddGameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    /// A dropped or chosen folder, or a game's .exe (its folder is used and the file preselected).
    var initial: URL? = nil
    /// Adding a Windows app rather than a game.
    var isApp = false
    @State private var folder: URL?
    @State private var preferredExe: String?
    @State private var candidates: [ExecutableScanner.Candidate] = []
    @State private var selectedExe: String?
    @State private var name = ""
    @State private var prefixChoice: PrefixChoice = .new
    @State private var scanning = false
    @State private var showAdvanced = false

    enum PrefixChoice: Hashable {
        case new, existing(UUID)
        var existingID: UUID? { if case .existing(let id) = self { return id }; return nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isApp ? "Add a Windows App" : "Add a Windows Game").font(.title2.bold())
            Text(isApp ? "Choose the folder the app is installed in. Alloy finds the program to start and gives it its own environment. Many Windows apps work; some, especially ones that need drivers or Microsoft services, don't."
                       : "Choose the folder the game is installed in. Alloy finds the program to start and sets up everything else.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(folder.map { LogRedactor.redact($0.path) } ?? "No folder selected")
                    .foregroundStyle(folder == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Folder…") { pickFolder() }
            }
            if scanning { ProgressView("Scanning for executables…") }
            if folder != nil && !scanning {
                Text("Main executable").font(.headline)
                if candidates.isEmpty {
                    Text("No .exe files found in this folder.").foregroundStyle(Theme.warning)
                } else {
                    List(candidates, id: \.relativePath, selection: $selectedExe) { c in
                        HStack {
                            Text(c.relativePath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(c.machine?.rawValue ?? "Not a valid PE").font(.caption)
                                .foregroundStyle(c.machine?.isSupportedByWineOnMac == true ? Color.secondary : Theme.danger)
                        }
                        .tag(c.relativePath)
                    }
                    .frame(height: 180)
                    Text("The top entry is Alloy’s best guess. For Unreal Engine games, the launcher in the game’s root folder is usually right.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Name", text: $name)
                Disclosure(title: "Advanced", isExpanded: $showAdvanced, font: .body) {
                    Picker("Environment", selection: $prefixChoice) {
                        Text("Create a new environment for this game").tag(PrefixChoice.new)
                        ForEach(model.ownPrefixes) { Text($0.name).tag(PrefixChoice.existing($0.id)) }
                    }
                    .padding(.top, 6)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .primaryAction(Theme.accent)
                    .disabled(folder == nil || selectedExe == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            guard folder == nil, let initial else { return }
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: initial.path, isDirectory: &isFolder)
            if isFolder.boolValue { use(initial) } else {
                preferredExe = initial.lastPathComponent
                use(initial.deletingLastPathComponent())
            }
        }
    }

    func pickFolder() {
        guard let url = AppModel.chooseFolder(prompt: "Select Game Folder") else { return }
        use(url)
    }

    func use(_ url: URL) {
        folder = url
        name = url.lastPathComponent
        scanning = true
        Task.detached {
            let found = ExecutableScanner.scan(folder: url)
            await MainActor.run {
                candidates = found
                selectedExe = found.first(where: { $0.relativePath == preferredExe })?.relativePath
                    ?? found.first(where: { $0.score >= 0 })?.relativePath ?? found.first?.relativePath
                scanning = false
            }
        }
    }

    func add() {
        guard let folder, let exe = selectedExe else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var game = Game(name: trimmed, folder: folder, executableRelativePath: exe, artwork: ArtworkFinder.find(in: folder))
        let choice = model.graphicsDefault(for: game, existingPrefixID: prefixChoice.existingID)
        switch prefixChoice {
        case .new: game.prefixID = model.createPrefix(name: trimmed, runtime: choice.runtime)?.id
        case .existing(let id): game.prefixID = id
        }
        game.graphics.backend = choice.backend
        game.graphics.forceDX11 = choice.forceDX11
        game.graphics.dlss = isApp ? false : choice.dlss
        game.isApp = isApp
        game.notes = game.notes.isEmpty ? "Graphics default: \(choice.reason)" : game.notes
        model.add(game)
        dismiss()
    }
}

// MARK: - Install from a setup program

struct InstallGameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var initial: URL? = nil
    @State private var setup: URL?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install a Windows Game").font(.title2.bold())
            Text("For games that come as a setup program (setup.exe or .msi), such as offline installers. Alloy makes a new environment for the game, runs the setup there and adds the game when the setup finishes.")
                .foregroundStyle(.secondary)
            HStack {
                Text(setup.map { LogRedactor.redact($0.path) } ?? "No setup file selected")
                    .foregroundStyle(setup == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Setup File…") {
                    if let url = AppModel.chooseFile(types: ["exe", "msi"], prompt: "Choose Setup") { use(url) }
                }
            }
            TextField("Game name", text: $name)
            Label { Text("The setup runs with your user permissions, never as administrator. Only install software you trust. When it asks where to install, keep the folder it suggests.") } icon: { Icon("exclamationmark.shield") }.font(.callout).foregroundStyle(Theme.warning)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install") {
                    if let setup { model.installGame(from: setup, name: name.trimmingCharacters(in: .whitespaces)) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .primaryAction(Theme.accent)
                .disabled(setup == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || !model.hasGameEngine)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { if setup == nil, let initial { use(initial) } }
    }

    func use(_ url: URL) {
        setup = url
        name = GameInstaller.suggestedName(for: url)
    }
}
