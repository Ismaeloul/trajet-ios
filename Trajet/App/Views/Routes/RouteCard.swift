import SwiftUI

/// Una ruta guardada en la lista (sistema.md §7.15, F26): tarjeta OPACA con
/// la cadena de distintivos, la etiqueta «ahora» si es la que toca según el
/// servidor (`active_id`, R37), el nombre, «origen → destino» y «entre
/// semana · llego 09:00» (las etiquetas de R35 y R36, no las de B). La que
/// toca lleva además un canto interior de 2 pt en `accent`.
struct RouteCard: View {
    let route: SavedRoute
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack(alignment: .center, spacing: Metrics.Space.sm) {
                RouteLineChain(codes: route.legs.map { LineChainItem($0) })
                Spacer(minLength: Metrics.Space.xs)
                if isActive {
                    RouteActiveTag()
                }
            }
            Text(route.name.isEmpty ? "Ruta sin nombre" : route.name)
                .textLevel(.legTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let endpoints = RouteText.endpoints(route) {
                Text(endpoints)
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(RouteText.summary(route))
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
            if !route.legsWithoutDirection.isEmpty {
                Label(allDirectionsText, systemImage: "exclamationmark.triangle")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.warnText)
            }
        }
        .padding(Metrics.Size.cardPadding + Metrics.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RouteText.spoken(route, isActive: isActive))
    }

    /// «13 en todos los sentidos» (R32).
    private var allDirectionsText: String {
        let codes = route.legsWithoutDirection.map { $0.lineCode.isEmpty ? $0.lineName : $0.lineCode }
        return "\(RouteText.list(codes)) en \(RouteText.allDirections)"
    }
}

/// Lo que necesita un eslabón de la cadena de distintivos.
struct LineChainItem: Hashable, Sendable {
    var code: String
    var color: String

    init(code: String, color: String) {
        self.code = code
        self.color = color
    }

    init(_ leg: SavedLeg) {
        self.init(code: leg.lineCode.isEmpty ? leg.lineName : leg.lineCode, color: leg.lineColor)
    }

    init(_ leg: RouteDraft.LegDraft) {
        self.init(code: leg.lineCode.isEmpty ? leg.lineName : leg.lineCode, color: leg.lineColor)
    }

    init(_ leg: PlanLeg) {
        self.init(code: leg.lineCode.isEmpty ? leg.lineName : leg.lineCode, color: leg.lineColor)
    }
}

/// La cadena de distintivos de una ruta: unidos por un filete de 12 × 2 en
/// `ink3` (§7.15). Si no cabe, se estrecha (distintivos pequeños y filete
/// corto) antes que cortarse. Decorativa para VoiceOver: la tarjeta ya dice
/// las líneas.
struct RouteLineChain: View {
    let codes: [LineChainItem]

    var body: some View {
        if codes.isEmpty {
            Text("sin tramos")
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        } else {
            ViewThatFits(in: .horizontal) {
                chain(size: Metrics.Size.badge, gap: 12)
                chain(size: Metrics.Size.badgeSmall, gap: 6)
                chain(size: Metrics.Size.badgeSmall, gap: 2)
            }
            .accessibilityHidden(true)
        }
    }

    private func chain(size: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: Metrics.Space.xs) {
            ForEach(Array(codes.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.ink3)
                        .frame(width: gap, height: 2)
                }
                LineBadge(code: item.code, color: item.color, size: size)
            }
        }
        .fixedSize()
    }
}

/// «ahora»: la ruta que el tablero enseñaría ahora (la decide el servidor).
struct RouteActiveTag: View {
    var body: some View {
        Text("ahora")
            .textLevel(.label)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(Palette.accentFill))
            .accessibilityHidden(true)
    }
}

/// Los siete días (L M X J V S D; 0 = lunes, R36): botones redondos de 44 pt
/// (§7.15, B tenía 38), con relleno de acento si están marcados. Con letra
/// muy grande pasan a dos filas.
struct WeekdayPicker: View {
    let days: Set<Int>
    let onToggle: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    dayButton(day)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Metrics.Size.hit + 4), spacing: 2), count: 4),
                      alignment: .leading, spacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    dayButton(day)
                }
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let isOn = days.contains(day)
        return Button {
            onToggle(day)
        } label: {
            Text(RouteText.weekdayLetters[day])
                .font(.body.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(isOn ? Palette.onAccent : Palette.ink)
                .frame(width: Metrics.Size.hit - 4, height: Metrics.Size.hit - 4)
                .background(Circle().fill(isOn ? Palette.accentFill : Palette.surfaceHi))
                .frame(width: Metrics.Size.hit, height: Metrics.Size.hit)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RouteText.weekdayNames[day])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Tarjetas de ruta") {
    let routes = PreviewData.routes
    ScrollView {
        VStack(spacing: Metrics.Space.gutter) {
            ForEach(routes) { route in
                RouteCard(route: route, isActive: route.id == 3)
            }
            WeekdayPicker(days: [0, 1, 2, 3, 4]) { _ in }
        }
        .padding(Metrics.Space.gutter)
    }
    .background(Palette.bg)
}
#endif
