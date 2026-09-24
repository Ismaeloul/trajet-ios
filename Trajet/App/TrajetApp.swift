import SwiftUI

// ESQUELETO de la FASE 3: solo para comprobar en CI que el proyecto (dos
// apps, extension, tests) compila con Swift 6 estricto y los tokens de
// «Cristal». Lo sustituye la app de verdad.
@main
struct TrajetApp: App {
    var body: some Scene {
        WindowGroup {
            EsqueletoView()
        }
    }
}

struct EsqueletoView: View {
    var body: some View {
        VStack(spacing: Metrics.Space.l) {
            LineBadge(code: "J", color: "CEC73D", textColor: "#000000")
            Text("Trajet")
                .font(.title.bold())
                .foregroundStyle(Palette.ink)
            Text("Esqueleto de la v2")
                .foregroundStyle(Palette.ink2)
        }
        .padding()
        .cristal(.bar, cornerRadius: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }
}
