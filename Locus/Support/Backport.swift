import SwiftUI
import UIKit

/// NavigationStack on iOS 16+, stack-style NavigationView on iOS 15.
struct LocusNavStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// LabeledContent on iOS 16+, HStack replica on iOS 15.
struct LocusLabeledRow<Value: View>: View {
    private let title: String
    private let value: Value

    init(_ title: String, value text: String) where Value == Text {
        self.title = title
        self.value = Text(text)
    }

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent(title) { value }
        } else {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 12)
                value
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func locusMediumLargeDetents() -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.medium, .large])
        } else {
            self
        }
    }

    @ViewBuilder
    func locusScrollIndicatorsHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func locusScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

enum LegacyCompatibility {
    // iOS 15 has no per-list background API; the appearance proxy is the only
    // way to keep List rows transparent over the map backdrop.
    static func applyListAppearance() {
        if #unavailable(iOS 16.0) {
            UITableView.appearance().backgroundColor = .clear
        }
    }
}

enum SFSymbolCompat {
    // SF Symbols 4 glyphs render blank on iOS 15; fall back to the closest
    // SF Symbols 3 equivalents there.
    static func resolved(_ name: String) -> String {
        if #available(iOS 16.0, *) { return name }
        switch name {
        case "figure.run": return "hare.fill"
        case "square.3.layers.3d": return "square.stack.3d.up.fill"
        case "road.lanes": return "point.topleft.down.curvedto.point.bottomright.up"
        default: return name
        }
    }
}

/// Native text-field alert on iOS 16+; UIAlertController on iOS 15, whose
/// SwiftUI alert cannot host text fields.
struct LocusRenameAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let placeholder: String
    @Binding var text: String
    var onSave: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.alert(title, isPresented: $isPresented) {
                TextField(placeholder, text: $text)
                Button("取消", role: .cancel) {}
                Button("保存") { onSave() }
                    .disabled(!canSave)
            } message: {
                Text(message)
            }
        } else {
            content.onChange(of: isPresented) { shown in
                guard shown else { return }
                DispatchQueue.main.async {
                    Self.presentUIKitAlert(
                        title: title,
                        message: message,
                        placeholder: placeholder,
                        initialText: text,
                        canSave: canSave
                    ) { newText in
                        text = newText
                        onSave()
                        isPresented = false
                    } onCancel: {
                        isPresented = false
                    }
                }
            }
        }
    }

    private static func presentUIKitAlert(
        title: String,
        message: String,
        placeholder: String,
        initialText: String,
        canSave: Bool,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
            var base = window.rootViewController else {
            onCancel()
            return
        }
        while let presented = base.presentedViewController {
            base = presented
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let emptyGuard = TextFieldEmptyGuard()

        alert.addTextField { field in
            field.placeholder = placeholder
            field.text = initialText
            field.addTarget(emptyGuard, action: #selector(TextFieldEmptyGuard.textChanged(_:)), for: .editingChanged)
        }

        let save = UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
            onSave(alert?.textFields?.first?.text ?? "")
        }
        save.isEnabled = canSave || !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        alert.addAction(save)

        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            onCancel()
        })

        emptyGuard.alert = alert
        base.present(alert, animated: true)
    }
}

/// Keeps the save action of a rename alert disabled until the field has
/// non-whitespace content. Retained by the text field's target/action.
private final class TextFieldEmptyGuard: NSObject {
    weak var alert: UIAlertController?

    @objc func textChanged(_ sender: UITextField) {
        guard let save = alert?.actions.last else { return }
        save.isEnabled = !(sender.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

extension View {
    func locusRenameAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        placeholder: String = "名称",
        text: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(
            LocusRenameAlertModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                placeholder: placeholder,
                text: text,
                onSave: onSave
            )
        )
    }
}
