import SwiftUI

/// El aviso de perturbación, DENTRO de la tarjeta del tramo.
///
/// No va en una franja global arriba porque una franja global no dice *qué*
/// tramo está tocado, y con cinco tramos eso es justo lo único que importa.
struct DisruptionNotice: View {
    let status: LegStatus
    let onSearchAlternative: () -> Void

    private var accent: Color {
        status.isInterrupted ? Palette.bad : Palette.warn
    }

    private var symbol: String {
        status.isInterrupted ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.label.capitalized)
                        .font(.system(size: 12, weight: .heavy))
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .foregroundStyle(accent)

                    ForEach(Array(status.visibleMessages.prefix(2).enumerated()),
                            id: \.offset) { _, message in
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: onSearchAlternative) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .bold))
                        Text("Buscar alternativa")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 44)
                    .background(
                        Capsule().fill(accent.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // El aviso llega en francés y se traduce en segundo plano. Se
                // dice para que el texto en francés no parezca un fallo.
                if status.awaitingTranslation {
                    TranslatingChip()
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }
}

/// «Traduciendo», con un latido suave. Nunca se espera al modelo para pintar.
struct TranslatingChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "character.bubble")
                .font(.system(size: 9, weight: .bold))
            Text("Traduciendo")
                .font(.system(size: 9.5, weight: .heavy))
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .foregroundStyle(Palette.inkFaint)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                dim = true
            }
        }
        .accessibilityLabel("Traduciendo el aviso")
    }
}

#if DEBUG
#Preview("Avisos") {
    VStack(spacing: 16) {
        DisruptionNotice(status: PreviewData.fiveLegBoard.legs[3].status) {}
        DisruptionNotice(status: PreviewData.fiveLegBoard.legs[4].status) {}
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Palette.background)
}
#endif
