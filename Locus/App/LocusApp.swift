import SwiftUI

@main
struct LocusApp: App {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false

    /// Map when setup finished, or when already paired outside this walkthrough.
    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMap {
                    RootView()
                } else {
                    SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile)) {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .preferredColorScheme(session.appearanceMode.colorScheme)
            .onOpenURL { url in
                handleIncoming(url)
            }
            .onAppear {
                if !setupComplete, pairing.hasPairingFile, !SetupGate.isInProgress {
                    SetupGate.markComplete()
                    setupComplete = true
                }
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        if url.scheme == "locus", url.host == "stop" {
            session.stopJoystick()
            session.discardRoute()
            session.stop(pairing: pairing)
            return
        }

        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            try? pairing.importPairing(from: url)
        } else if ext == "gpx" {
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
