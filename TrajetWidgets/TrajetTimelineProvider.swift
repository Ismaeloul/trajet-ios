import SwiftUI
import WidgetKit

// El timeline de los widgets (docs/diseno/sistema.md §12.7). La lógica está
// en Trajet/Shared/Components/WidgetTimeline.swift (probada en
// WidgetTimelineTests); aquí solo se lee la caché y se entrega a WidgetKit.
//
// La extensión no llama al servidor: no tiene el cliente (TrajetAPI vive en
// la app) ni el token. Pinta el último tablero que la app dejó en el App
// Group, tal como llegó, con su antigüedad a la vista, y acaba en «Sin datos
// recientes · abre Trajet» cuando se le acaban las salidas.

/// Una entrada del timeline: la foto (`WidgetSnapshot`) en su fecha.
struct TrajetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.date = snapshot.date
        self.snapshot = snapshot
    }
}

struct TrajetTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> TrajetEntry {
        TrajetEntry(snapshot: .sample(now: Date()))
    }

    // Firmas como el esqueleto que ya compiló en el CI (sin @Sendable).
    func getSnapshot(in context: Context, completion: @escaping (TrajetEntry) -> Void) {
        let now = Date()
        let plan = Self.plan(now: now)
        // En la galería, sin tablero todavía, se enseña la forma del widget
        // (sin App Group se dice la verdad también ahí).
        if context.isPreview, plan.snapshots.first?.content == .noBoard {
            completion(TrajetEntry(snapshot: .sample(now: now)))
            return
        }
        completion(TrajetEntry(snapshot: plan.snapshots.first
                               ?? WidgetSnapshot(date: now, content: .noBoard, failure: nil, countdownValid: true)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrajetEntry>) -> Void) {
        let plan = Self.plan(now: Date())
        let entries = plan.snapshots.map { TrajetEntry(snapshot: $0) }
        let policy: TimelineReloadPolicy = plan.reloadDate.map { .after($0) } ?? .never
        completion(Timeline(entries: entries, policy: policy))
    }

    /// La caché del App Group (la escribe la app en cada refresco) y el fallo
    /// que haya apuntado después. Sin App Group (IPA full firmada con un
    /// Apple ID gratuito) no hay nada que leer: el widget lo dice.
    static func plan(now: Date) -> WidgetTimelinePlan {
        let hasGroup = Capabilities.hasAppGroup
        let cached = hasGroup ? BoardCache.load() : nil
        let failure = cached.flatMap { WidgetRefresher.recordedFailure(after: $0.receivedAt) }
        return WidgetTimelinePlanner.plan(cached: cached, hasAppGroup: hasGroup, failure: failure, now: now)
    }
}
