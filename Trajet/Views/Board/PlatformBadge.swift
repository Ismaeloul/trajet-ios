import SwiftUI

/// La vía.
///
/// Es la regla que el manual marca como no negociable: **el andén probable no
/// puede leerse jamás como el real**. Por eso no se distinguen por un matiz de
/// color, que a contraluz se pierde, sino por tres cosas a la vez:
///
///   · caja **sólida** con la palabra «Vía» ....... es la de verdad
///   · recuadro **punteado** con «probable» ....... la ha deducido el histórico
///
/// Y cuando la vía acaba de aparecer —el momento en que hay que echar a
/// andar— la caja sólida se pone amarilla y da un latido. Solo aparece en el
/// 17 % de los trenes y con 7,7 min de mediana: cuando pasa, hay que verlo.
struct PlatformBadge: View {

    enum Kind {
        case real(String, isNew: Bool)
        case guessed(PlatformGuess)
    }

    let kind: Kind
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        switch kind {
        case .real(let number, let isNew):
            realBadge(number, isNew: isNew)
        case .guessed(let guess):
            guessBadge(guess)
        }
    }

    // ---------------- vía confirmada ----------------

    private func realBadge(_ number: String, isNew: Bool) -> some View {
        HStack(spacing: 3) {
            Text("Vía")
                .font(.system(size: compact ? 8.5 : 9.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.4)
                .opacity(0.62)
            Text(number)
                .font(.system(size: compact ? 14 : 16, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isNew ? Color(red: 1.0, green: 0.84, blue: 0.16) : Color.white)
        )
        .scaleEffect(pulse ? 1.06 : 1)
        .shadow(color: isNew ? Color(red: 1, green: 0.84, blue: 0.16).opacity(0.5) : .clear,
                radius: pulse ? 10 : 4)
        .onAppear {
            guard isNew, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.65).repeatCount(5, autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isNew ? "Acaba de salir la vía \(number)" : "Vía \(number)")
    }

    // ---------------- vía solo probable ----------------

    private func guessBadge(_ guess: PlatformGuess) -> some View {
        HStack(spacing: 3) {
            Text(guess.platform)
                .font(.system(size: compact ? 13 : 14, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("probable")
                .font(.system(size: compact ? 8 : 8.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.3)
                .opacity(0.85)
        }
        .foregroundStyle(Palette.inkMuted)
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    Palette.inkFaint,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                )
        )
        .accessibilityElement()
        .accessibilityLabel(
            "Vía \(guess.platform) probable, \(guess.percent) por ciento "
            + "sobre \(guess.samples) observaciones, \(guess.why)"
        )
    }
}

#if DEBUG
#Preview("Vías") {
    VStack(alignment: .leading, spacing: 14) {
        PlatformBadge(kind: .real("21", isNew: false))
        PlatformBadge(kind: .real("11", isNew: true))
        PlatformBadge(kind: .guessed(.preview))
        PlatformBadge(kind: .guessed(.preview), compact: true)
    }
    .padding(30)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
}
#endif
