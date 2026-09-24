import SwiftUI
import WidgetKit

// ESQUELETO de la FASE 3: un widget minimo para comprobar que la extension
// compila y se embebe en la IPA full. Lo sustituyen los widgets de verdad
// (docs/diseno/decisiones-la-widgets.md).
@main
struct TrajetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EsqueletoWidget()
    }
}

struct EsqueletoEntry: TimelineEntry {
    let date: Date
}

struct EsqueletoProvider: TimelineProvider {
    func placeholder(in context: Context) -> EsqueletoEntry { EsqueletoEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (EsqueletoEntry) -> Void) {
        completion(EsqueletoEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EsqueletoEntry>) -> Void) {
        completion(Timeline(entries: [EsqueletoEntry(date: .now)], policy: .never))
    }
}

struct EsqueletoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "esqueleto", provider: EsqueletoProvider()) { _ in
            Text("Trajet").foregroundStyle(Palette.ink)
                .containerBackground(Palette.surface, for: .widget)
        }
        .configurationDisplayName("Trajet")
        .supportedFamilies([.systemSmall])
    }
}
