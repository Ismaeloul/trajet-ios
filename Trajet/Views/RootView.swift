import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case board, routes, plan, stats

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: "Tablero"
        case .routes: "Rutas"
        case .plan: "Buscar"
        case .stats: "Historial"
        }
    }

    var symbol: String {
        switch self {
        case .board: "clock.fill"
        case .routes: "map.fill"
        case .plan: "magnifyingglass"
        case .stats: "chart.bar.fill"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .board
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            Group {
                switch tab {
                case .board: BoardView(showSettings: $showSettings)
                case .routes: RoutesView()
                case .plan: PlanView()
                case .stats: StatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PillTabBar(selection: $tab)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // El refresco solo corre mientras el tablero está delante y la app en
        // pantalla. Son 1000 llamadas al día: en segundo plano se para.
        .onChange(of: scenePhase, initial: true) { _, phase in
            syncRefresh(phase: phase, tab: tab)
        }
        .onChange(of: tab) { _, newTab in
            syncRefresh(phase: scenePhase, tab: newTab)
        }
    }

    private func syncRefresh(phase: ScenePhase, tab: AppTab) {
        if phase == .active && tab == .board {
            model.board.start()
        } else {
            model.board.stop()
        }
    }
}

/// La barra inferior: una pastilla flotante en la que solo la pestaña activa
/// lleva etiqueta. Las inactivas son iconos, pero conservan sus 44 pt.
struct PillTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isActive = tab == selection

                Button {
                    guard !isActive else { return }
                    withAnimation(.snappy(duration: 0.28)) { selection = tab }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: isActive ? 15 : 18, weight: .semibold))
                        if isActive {
                            Text(tab.label)
                                .font(.system(size: 14, weight: .bold))
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .foregroundStyle(isActive ? Palette.ink : Palette.inkFaint)
                    .padding(.horizontal, isActive ? 16 : 0)
                    .frame(minWidth: 48, minHeight: 48)
                    .background {
                        if isActive {
                            Capsule(style: .continuous)
                                .fill(Palette.surfaceHi)
                                .matchedGeometryEffect(id: "activePill", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}
