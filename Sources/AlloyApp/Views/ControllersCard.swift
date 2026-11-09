import AlloyCore
import GameController
import SwiftUI

/// Controllers macOS sees right now, updated as they connect and disconnect.
@MainActor
final class ControllerMonitor: ObservableObject {
    struct Controller: Identifiable, Equatable {
        let id: ObjectIdentifier
        let name: String
        let category: String
    }

    @Published private(set) var controllers: [Controller] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        GCController.startWirelessControllerDiscovery {}
        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        GCController.stopWirelessControllerDiscovery()
    }

    func refresh() {
        controllers = GCController.controllers().map {
            Controller(id: ObjectIdentifier($0), name: $0.vendorName ?? $0.productCategory, category: $0.productCategory)
        }
    }
}

/// Game controllers, below Scrolling on the game's page: what is connected and how games will see it, and Wine's own
/// controller test in the game's environment.
struct ControllersCard: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var monitor = ControllerMonitor()
    let game: Game

    var body: some View {
        Panel("Controllers") {
            if monitor.controllers.isEmpty {
                Text("No controller connected. \(GameControllers.help)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(monitor.controllers) { controller in
                    HStack(alignment: .top, spacing: 10) {
                        Icon("gamecontroller").foregroundStyle(Theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.name)
                            Text(GameControllers.summary(GameControllers.reach(productCategory: controller.category)))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let prefix = model.prefix(game.prefixID) {
                HStack {
                    Button("Test in Wine…") { model.open(.gameControllers, in: prefix) }
                    Spacer()
                }
            }
        }
    }
}
