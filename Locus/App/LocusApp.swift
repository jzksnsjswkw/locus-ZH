import SwiftUI

@main
struct LocusApp: App {
    @StateObject private var session = SpoofSession()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    /// Map when setup is finished.
    private var showMap: Bool {
        setupComplete
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMap {
                    RootView()
                } else {
                    SetupFlowView {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .preferredColorScheme(session.appearanceMode.colorScheme)
            .onOpenURL { url in
                handleIncoming(url)
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        if url.scheme == "locus", url.host == "stop" {
            session.stopJoystick()
            session.discardRoute()
            session.stop()
            return
        }

        if url.pathExtension.lowercased() == "gpx" {
            NotificationCenter.default.post(name: .locusImportGPX, object: url)
        }
    }
}

extension Notification.Name {
    static let locusImportGPX = Notification.Name("locusImportGPX")
    static let locusDeleteRoute = Notification.Name("locusDeleteRoute")
    static let locusRunRoute = Notification.Name("locusRunRoute")
    static let locusBuildRouteToTarget = Notification.Name("locusBuildRouteToTarget")
    static let locusCancelDrawingRoute = Notification.Name("locusCancelDrawingRoute")
    static let locusUndoDrawingPoint = Notification.Name("locusUndoDrawingPoint")
    static let locusSaveDrawingRoute = Notification.Name("locusSaveDrawingRoute")
    static let locusDismissStatusDetails = Notification.Name("locusDismissStatusDetails")
}
