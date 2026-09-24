import SwiftUI

/// Un estado que no es el feliz, dicho con palabras (R53): icono, qué pasa,
/// qué hacer y los botones para hacerlo. Tarjeta opaca, centrada. Lo usan
/// el tablero (vacío, error sin caché, servidor sin clave…) y cualquier
/// pantalla que necesite decir «aquí no hay nada, y por esto».
///
/// «Tiene que decir qué hacer, no solo que está vacío.»
struct MessageStateView<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String?
    let actions: Actions

    init(symbol: String, tint: Color = Palette.ink3, title: String, message: String? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Metrics.Space.ml) {
            Image(systemName: symbol)
                .font(.largeTitle.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityHidden(true)
            VStack(spacing: Metrics.Space.xs) {
                Text(title)
                    .textLevel(.legTitle)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message, !message.isEmpty {
                    Text(message)
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Metrics.Space.sm) {
                actions
            }
            .padding(.top, Metrics.Space.xs)
        }
        .padding(.vertical, Metrics.Space.xxl)
        .padding(.horizontal, Metrics.Space.xl)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }
}

extension MessageStateView where Actions == EmptyView {
    init(symbol: String, tint: Color = Palette.ink3, title: String, message: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, message: message) { EmptyView() }
    }
}

#if DEBUG
#Preview("Estado con palabras") {
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            MessageStateView(symbol: "wifi.slash", tint: Palette.badText,
                             title: "No se llega al servidor",
                             message: "Ni por la red de casa ni por Tailscale.") {
                Button {} label: { Label("Reintentar", systemImage: "arrow.clockwise") }
                    .filledButton()
            }
            MessageStateView(symbol: "moon.zzz", title: "Nada por aquí")
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
