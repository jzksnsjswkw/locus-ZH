import MapKit
import SwiftUI
import UIKit
import Vision

enum MapDataSource: String {
    case apple = "Apple"
    case amap = "高德"
    case unknown = ""

    var displayName: String? {
        self == .unknown ? nil : rawValue
    }
}

@MainActor
final class MapDataSourceDetector: ObservableObject {
    @Published private(set) var source: MapDataSource = .unknown

    private weak var probeView: UIView?
    private var scheduledDetection: Task<Void, Never>?
    private var ocrInFlight = false

    func attach(to view: UIView) {
        guard probeView !== view else { return }
        probeView = view
        scheduleDetection()
    }

    func scheduleDetection() {
        scheduledDetection?.cancel()
        source = .unknown
        scheduledDetection = Task { [weak self] in
            for delay in [0.35, 1.0, 2.0] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                guard let self else { return }
                detectNow()
            }
        }
    }

    func redetect() {
        source = .unknown
        detectNow()
    }

    private func detectNow() {
        guard let window = probeView?.window,
              let mapView = bestVisibleMapView(in: window) else { return }

        let treeResult = detectFromViewTree(mapView)
        if treeResult == .amap {
            commit(.amap)
            return
        }
        detectByOCR(mapView, fallback: treeResult)
    }

    private func commit(_ detected: MapDataSource) {
        guard detected != .unknown else { return }
        if source != detected {
            source = detected
        }
    }

    private func bestVisibleMapView(in window: UIWindow) -> MKMapView? {
        collectMapViews(in: window)
            .filter { !$0.isHidden && $0.alpha > 0.01 && $0.window === window }
            .max { visibleArea(of: $0, in: window) < visibleArea(of: $1, in: window) }
    }

    private func collectMapViews(in view: UIView) -> [MKMapView] {
        var result: [MKMapView] = []
        if let mapView = view as? MKMapView {
            result.append(mapView)
        }
        for subview in view.subviews {
            result.append(contentsOf: collectMapViews(in: subview))
        }
        return result
    }

    private func visibleArea(of view: UIView, in window: UIWindow) -> CGFloat {
        let rect = view.convert(view.bounds, to: window).intersection(window.bounds)
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

    private func detectFromViewTree(_ mapView: MKMapView) -> MapDataSource? {
        classify(collectStrings(from: mapView).joined(separator: " "))
    }

    private func collectStrings(from view: UIView) -> [String] {
        var strings: [String] = []
        if let label = view as? UILabel, let text = nonEmpty(label.text) {
            strings.append(text)
        }
        if let textView = view as? UITextView, let text = nonEmpty(textView.text) {
            strings.append(text)
        }
        if let button = view as? UIButton, let text = nonEmpty(button.titleLabel?.text) {
            strings.append(text)
        }
        if let label = nonEmpty(view.accessibilityLabel) {
            strings.append(label)
        }
        if let value = nonEmpty(view.accessibilityValue) {
            strings.append(value)
        }
        for subview in view.subviews {
            strings.append(contentsOf: collectStrings(from: subview))
        }
        return strings
    }

    private func classify(_ text: String) -> MapDataSource? {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if normalized.contains("高德地图") ||
            normalized.contains("高德") ||
            normalized.contains("amap") ||
            normalized.contains("autonavi") {
            return .amap
        }
        if normalized.contains("apple maps") ||
            normalized.contains("apple 地图") ||
            normalized.contains("apple地图") ||
            normalized.contains("maps by apple") ||
            normalized.contains("maps") ||
            (normalized.contains("maps") && normalized.contains("legal")) {
            return .apple
        }
        return nil
    }

    private func detectByOCR(_ mapView: MKMapView, fallback: MapDataSource?) {
        guard !ocrInFlight else { return }
        guard let image = captureAttributionCorners(from: mapView),
              let cgImage = image.cgImage else {
            if let fallback { commit(fallback) }
            return
        }

        ocrInFlight = true
        let request = VNRecognizeTextRequest { [weak self] request, error in
            let text: String
            if error == nil, let observations = request.results as? [VNRecognizedTextObservation] {
                text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
            } else {
                text = ""
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                ocrInFlight = false
                if let detected = classify(text) ?? fallback {
                    commit(detected)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        DispatchQueue.global(qos: .utility).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try? handler.perform([request])
        }
    }

    private func captureAttributionCorners(from mapView: MKMapView) -> UIImage? {
        guard mapView.bounds.width > 1, mapView.bounds.height > 1 else { return nil }
        let cropWidth = min(260, mapView.bounds.width / 2)
        let cropHeight = min(140, mapView.bounds.height)
        let leftRect = CGRect(x: 0, y: mapView.bounds.maxY - cropHeight, width: cropWidth, height: cropHeight)
        let rightRect = CGRect(
            x: mapView.bounds.maxX - cropWidth,
            y: mapView.bounds.maxY - cropHeight,
            width: cropWidth,
            height: cropHeight
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: cropWidth * 2, height: cropHeight),
            format: format
        )
        return renderer.image { context in
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight))
            context.cgContext.translateBy(x: -leftRect.minX, y: -leftRect.minY)
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
            context.cgContext.restoreGState()

            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: cropWidth, y: 0, width: cropWidth, height: cropHeight))
            context.cgContext.translateBy(x: cropWidth - rightRect.minX, y: -rightRect.minY)
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
            context.cgContext.restoreGState()
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

struct MapDataSourceProbe: UIViewRepresentable {
    let detector: MapDataSourceDetector

    func makeUIView(context: Context) -> MapDataSourceProbeView {
        let view = MapDataSourceProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onAttachedToWindow = { [weak detector] probe in
            detector?.attach(to: probe)
        }
        return view
    }

    func updateUIView(_ uiView: MapDataSourceProbeView, context: Context) {
        if uiView.window != nil {
            detector.attach(to: uiView)
        }
    }
}

final class MapDataSourceProbeView: UIView {
    var onAttachedToWindow: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachedToWindow?(self)
        }
    }
}
