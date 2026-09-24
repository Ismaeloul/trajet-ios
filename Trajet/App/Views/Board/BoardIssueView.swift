import SwiftUI

/// Los estados diseñados de `BoardIssue` cuando NO hay tablero guardado que
/// enseñar (con tablero, se enseña el tablero y la píldora dice lo que pasa,
/// R9). Es el único caso en que la pantalla se queda sin tablero, y entonces
/// dice por qué y qué hacer (R53, sistema.md §7.18):
///
/// - sin conexión: «No se llega al servidor» + «Ni por la red de casa ni por
///   Tailscale.» + «Reintentar»;
/// - servidor sin clave (`prim_key_missing`): diseñado, no un error genérico,
///   con acceso a los ajustes del servidor;
/// - clave rechazada, cuota agotada, PRIM caído, error del servidor;
/// - sin emparejar (401): «Emparejar de nuevo».
struct BoardIssueView: View {
    let issue: BoardIssue
    var isRetrying: Bool = false
    var onRetry: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRepair: () -> Void = {}

    var body: some View {
        MessageStateView(symbol: BoardIssueCopy.symbol(issue), tint: tint,
                         title: BoardIssueCopy.title(issue),
                         message: BoardIssueCopy.message(issue)) {
            if BoardIssueCopy.offersRepair(issue) {
                Button(action: onRepair) {
                    Label("Emparejar de nuevo", systemImage: "qrcode.viewfinder")
                }
                .filledButton(.primary)
            }
            if BoardIssueCopy.offersServerSettings(issue) {
                Button(action: onOpenSettings) {
                    Label("Ajustes del servidor", systemImage: "server.rack")
                }
                .filledButton(.primary)
            }
            if BoardIssueCopy.allowsRetry(issue) {
                Button(action: onRetry) {
                    HStack(spacing: Metrics.Space.sm) {
                        if isRetrying {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Reintentar")
                    }
                    .frame(maxWidth: .infinity)
                }
                .cristalButton()
                .controlSize(.large)
                .disabled(isRetrying)
            }
        }
    }

    private var tint: Color {
        switch issue {
        case .offline, .noKey, .keyRejected, .notPaired: Palette.badText
        case .quotaExhausted, .upstream, .other: Palette.warnText
        }
    }
}

#if DEBUG
#Preview("Estados de error sin tablero") {
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            BoardIssueView(issue: .offline(""))
            BoardIssueView(issue: .noKey)
            BoardIssueView(issue: .quotaExhausted(retryAfter: 3600))
            BoardIssueView(issue: .notPaired)
            BoardIssueView(issue: .offline(""), isRetrying: true)
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
