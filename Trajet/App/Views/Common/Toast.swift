import SwiftUI
import UIKit

// Avisos efímeros (R55): «Ruta guardada», «Esa ruta ya no existe»… Una
// cápsula de cristal encima de la barra de pestañas durante 2,4 s, que entra
// con muelle desde abajo (fundido con «Reducir movimiento») y se anuncia a
// VoiceOver. Nunca un diálogo que corte el paso (sistema.md §7.18).
//
// Uso: `MainTabView` crea el `ToastCenter` (dentro de `AppNavigator`), lo
// pone en el entorno y lo pinta con `.toastHost(_:)`. Cualquier pantalla:
//
// ```swift
// @Environment(ToastCenter.self) private var toasts: ToastCenter?
// toasts?.show("Ruta borrada", symbol: "trash")
// ```

/// Un aviso efímero.
struct ToastMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Símbolo SF opcional delante del texto.
    let symbol: String?

    init(id: UUID = UUID(), text: String, symbol: String? = nil) {
        self.id = id
        self.text = text
        self.symbol = symbol
    }
}

/// Quién enseña los avisos efímeros. Uno a la vez: el nuevo sustituye al
/// anterior.
@MainActor
@Observable
final class ToastCenter {
    /// Lo que dura en pantalla (R55: 2,4 s).
    nonisolated static let duration: TimeInterval = Motion.Timing.toast
    /// Separación del borde de abajo, para quedar encima de la barra de
    /// pestañas.
    nonisolated static let bottomInset: CGFloat = 64

    /// El aviso que se ve ahora.
    private(set) var current: ToastMessage?

    init() {}

    /// Enseña un aviso (y lo dice VoiceOver).
    @discardableResult
    func show(_ text: String, symbol: String? = nil) -> ToastMessage {
        let message = ToastMessage(text: text, symbol: symbol)
        current = message
        UIAccessibility.post(notification: .announcement, argument: text)
        return message
    }

    /// Quita el aviso. Con `id`, solo si sigue siendo ese (así un
    /// temporizador viejo no se lleva uno nuevo).
    func dismiss(_ id: UUID? = nil) {
        guard let current else { return }
        if let id, id != current.id { return }
        self.current = nil
    }
}

/// La cápsula del aviso.
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            if let symbol = message.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.ink2)
                    .accessibilityHidden(true)
            }
            Text(message.text)
                .textLevel(.bodyStrong)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Metrics.Space.l)
        .padding(.vertical, Metrics.Space.ml)
        .frame(minHeight: Metrics.Size.hit)
        .cristal(.panel, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Pinta los avisos efímeros de `center` encima de esta vista.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let message = center.current {
                    ToastView(message: message)
                        .padding(.horizontal, Metrics.Space.gutter)
                        .padding(.bottom, ToastCenter.bottomInset)
                        .id(message.id)
                        .transition(transition)
                        .onTapGesture { center.dismiss(message.id) }
                }
            }
            .animation(Motion.animation(.morph, reduceMotion: reduceMotion), value: center.current?.id)
            .task(id: center.current?.id) {
                guard let id = center.current?.id else { return }
                try? await Task.sleep(for: .seconds(ToastCenter.duration))
                center.dismiss(id)
            }
        }
    }

    private var transition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }
}

#if DEBUG
private struct ToastPreview: View {
    @State private var center = ToastCenter()

    var body: some View {
        VStack(spacing: Metrics.Space.l) {
            Button("Ruta guardada") { center.show("Ruta guardada", symbol: "checkmark") }
                .filledButton()
            Button("Esa ruta ya no existe") {
                center.show("Esa ruta ya no existe", symbol: "exclamationmark.triangle")
            }
            .cristalButton()
        }
        .padding(Metrics.Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .toastHost(center)
        .onAppear { center.show("Ruta guardada", symbol: "checkmark") }
    }
}

#Preview("Aviso efímero") {
    ToastPreview()
}
#endif
