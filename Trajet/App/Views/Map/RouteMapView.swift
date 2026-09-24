import MapKit
import SwiftUI

/// Cómo se enseña el mapa de una ruta.
enum RouteMapStyle: Hashable, Sendable {
    /// Cabecera del tablero: sin interacción, sin etiquetas, solo el trazado
    /// con la subida y la bajada (docs/diseno/sistema.md §7.1).
    case header
    /// El mapa entero (MapScreen): trazado, paradas, transbordos, mi
    /// posición y el camino a pie.
    case full
}

/// Dónde está la vía del tren que toca (con coordenadas de las vías SNCF del
/// mapa), para señalarla en la estación.
struct MapPlatformHint: Hashable, Sendable {
    var point: GeoPoint
    var platform: String
    /// Vía real (caja sólida) o probable (recuadro punteado, R10).
    var isReal: Bool
}

/// El mapa de una ruta (GET /api/v1/routes/{id}/map, `MapStore`).
///
/// Estilo «Cristal» (docs/diseno/sistema.md §3.7): mapa base apagado y todo
/// el color en los trazados, con el color oficial de cada línea sobre un
/// contorno. Polilínea `coarse` de lejos y `fine` de cerca (cambia con la
/// distancia de la cámara). Sin trazado todavía (`pending`) o sin trazado de
/// verdad: recta discreta entre paradas. No hay posición de trenes en vivo:
/// no se pinta ninguna. Entre andenes no hay camino en los datos abiertos: en
/// los transbordos va solo el tiempo mínimo.
struct RouteMapView: View {
    let routeID: Int
    let style: RouteMapStyle
    private let walkingPath: [GeoPoint]
    private let scope: Namespace.ID?
    private let platform: MapPlatformHint?
    private let recenter: Int

    @Environment(AppServices.self) private var services
    @State private var position: MapCameraPosition = .region(RouteMapDetail.parisRegion)
    @State private var useFine = false
    @State private var geometry: RouteMapGeometry? = nil
    @State private var framedRouteID: Int? = nil

    /// Para el tablero y cualquier sitio que solo quiera el mapa.
    init(routeID: Int, style: RouteMapStyle) {
        self.init(routeID: routeID, style: style, walkingPath: [], scope: nil, platform: nil, recenter: 0)
    }

    /// Para MapScreen: el camino a pie, el ámbito de los controles
    /// (`MapUserLocationButton`), la vía del tren que toca y un contador que,
    /// al cambiar, vuelve a encuadrar la ruta.
    init(routeID: Int, style: RouteMapStyle, walkingPath: [GeoPoint], scope: Namespace.ID?,
         platform: MapPlatformHint?, recenter: Int) {
        self.routeID = routeID
        self.style = style
        self.walkingPath = walkingPath
        self.scope = scope
        self.platform = platform
        self.recenter = recenter
    }

    var body: some View {
        let key = services.maps.map(for: routeID).map(RouteMapGeometry.key(for:))
        content
            .task(id: routeID) {
                await services.maps.load(routeID: routeID)
            }
            .onChange(of: key, initial: true) {
                rebuild()
            }
            .onChange(of: recenter) {
                frame(animated: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if style == .header && geometry == nil {
            // Sin mapa aún: el fondo, no el mapamundi.
            Rectangle()
                .fill(Palette.surfaceHi)
                .accessibilityHidden(true)
        } else {
            mapView
        }
    }

    private var mapView: some View {
        Map(position: $position,
            interactionModes: style == .full ? [.pan, .zoom] : [],
            scope: scope) {
            if let geometry {
                routeContent(geometry)
            }
            if style == .full {
                walkingContent
                platformContent
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {}
        .annotationTitles(style == .header ? .hidden : .automatic)
        .onMapCameraChange(frequency: .onEnd) { context in
            let fine = RouteMapDetail.useFine(cameraDistance: context.camera.distance, current: useFine)
            if fine != useFine { useFine = fine }
        }
        .allowsHitTesting(style == .full)
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        style == .header ? "Mapa de la ruta" : "Mapa"
    }

    // MARK: - Contenido

    @MapContentBuilder
    private func routeContent(_ g: RouteMapGeometry) -> some MapContent {
        // Sin trazado de verdad: recta discreta (fina y translúcida, sin
        // contorno). El punteado queda para «probable» y el camino a pie.
        ForEach(g.straightLines) { line in
            MapPolyline(coordinates: line.coarse)
                .stroke(LineColor.parse(line.colorHex).opacity(0.55),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(g.tracedLines) { line in
            MapPolyline(coordinates: line.coordinates(fine: useFine))
                .stroke(Palette.mapCasing,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(g.tracedLines) { line in
            MapPolyline(coordinates: line.coordinates(fine: useFine))
                .stroke(LineColor.parse(line.colorHex),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(style == .full ? g.dots : []) { dot in
            Annotation("", coordinate: dot.coordinate, anchor: .center) {
                Circle()
                    .fill(LineColor.parse(dot.colorHex))
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Parada \(dot.name)")
            }
        }
        ForEach(style == .full ? g.transfers : []) { transfer in
            Annotation("", coordinate: transfer.coordinate, anchor: .top) {
                TransferTag(text: transfer.label)
                    .padding(.top, 12)
            }
        }
        ForEach(style == .full ? g.stops : g.stops.filter { $0.role == .origin || $0.role == .destination }) { stop in
            Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                StationDot(role: stop.role, color: LineColor.parse(stop.colorHex))
                    .accessibilityLabel(stop.spoken)
            }
        }
    }

    /// El camino a pie hasta la estación (MKDirections), en puntos.
    @MapContentBuilder
    private var walkingContent: some MapContent {
        if walkingPath.count >= 2 {
            MapPolyline(coordinates: walkingPath.map(\.coordinate))
                .stroke(Palette.mapWalk,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [0.1, 6]))
        }
    }

    /// La vía del tren que toca, en su sitio de la estación.
    @MapContentBuilder
    private var platformContent: some MapContent {
        if let platform {
            Annotation("", coordinate: platform.point.coordinate, anchor: .bottom) {
                PlatformPin(platform: platform.platform, isReal: platform.isReal)
            }
        }
    }

    // MARK: - Geometría y encuadre

    private func rebuild() {
        guard let map = services.maps.map(for: routeID) else {
            geometry = nil
            return
        }
        geometry = RouteMapGeometry(map: map)
        // La cabecera se encuadra siempre; el mapa entero, una vez por ruta
        // (no se le quita la cámara a quien la está moviendo).
        if style == .header || framedRouteID != routeID {
            frame(animated: false)
        }
    }

    private func frame(animated: Bool) {
        guard let geometry, let rect = RouteMapDetail.frame(points: geometry.points, style: style) else { return }
        framedRouteID = routeID
        if animated {
            withAnimation(Motion.ease(0.6)) { position = .rect(rect) }
        } else {
            position = .rect(rect)
        }
    }
}

// MARK: - Piezas del mapa

/// Parada servida: círculo con relleno claro y el color de la línea (más
/// grande en la subida y la bajada).
private struct StationDot: View {
    let role: MapStation.Role
    let color: Color

    var body: some View {
        let side: CGFloat = (role == .origin || role == .destination) ? 14 : 10
        Circle()
            .fill(Palette.mapStopFill)
            .frame(width: side, height: side)
            .overlay(Circle().stroke(color, lineWidth: 2.5))
    }
}

/// «Transbordo · mín. 4 min» (de `min_transfer_s`).
private struct TransferTag: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "arrow.up.arrow.down")
            .textLevel(.label)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, Metrics.Space.xs)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: Metrics.Size.hairline))
            .fixedSize()
    }
}

/// La vía en el mapa: caja sólida «Vía 21» si es real, recuadro punteado
/// «probable 21» si no (R10).
private struct PlatformPin: View {
    let platform: String
    let isReal: Bool

    private var word: String { isReal ? "Vía" : "probable" }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.via, style: .continuous)
        HStack(spacing: Metrics.Space.xs) {
            Text(word)
                .textLevel(.label)
            Text(platform)
                .font(NumberLevel.font(size: 15).weight(.black))
        }
        .foregroundStyle(isReal ? Palette.viaInk : Palette.ink)
        .padding(.horizontal, Metrics.Space.sm)
        .padding(.vertical, Metrics.Space.xs)
        .background {
            if isReal {
                shape.fill(Palette.via)
                    .overlay(shape.strokeBorder(Palette.viaEdge, lineWidth: Metrics.Size.hairline))
            } else {
                shape.fill(Palette.surface)
                    .overlay(shape.strokeBorder(Palette.ink2,
                                                style: StrokeStyle(lineWidth: Metrics.Size.dashWidth,
                                                                   dash: Metrics.Size.dash)))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        isReal ? "Vía \(platform)" : "Vía \(platform) probable"
    }
}

// MARK: - Geometría ya decodificada

/// El mapa de una ruta listo para pintar: las polilíneas se decodifican una
/// vez por mapa, no en cada fotograma.
struct RouteMapGeometry {
    struct Line: Identifiable {
        let id: Int
        let code: String
        let colorHex: String
        let coarse: [CLLocationCoordinate2D]
        let fine: [CLLocationCoordinate2D]
        /// Sin trazado de verdad (recta entre paradas).
        let straight: Bool

        func coordinates(fine useFine: Bool) -> [CLLocationCoordinate2D] {
            useFine ? fine : coarse
        }
    }

    struct Stop: Identifiable {
        let id: String
        let name: String
        let role: MapStation.Role
        let coordinate: CLLocationCoordinate2D
        let colorHex: String

        var spoken: String {
            switch role {
            case .origin: "Subida en \(name)"
            case .destination: "Bajada en \(name)"
            case .transfer: "Transbordo en \(name)"
            case .other: name
            }
        }
    }

    /// Parada de paso.
    struct Dot: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let colorHex: String
    }

    struct Transfer: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let label: String
    }

    let lines: [Line]
    let stops: [Stop]
    let dots: [Dot]
    let transfers: [Transfer]
    /// Todo lo que hay que encuadrar.
    let points: [GeoPoint]

    var tracedLines: [Line] { lines.filter { !$0.straight } }
    var straightLines: [Line] { lines.filter(\.straight) }

    init(map: RouteMap) {
        let ordered = map.lines.sorted { $0.seq < $1.seq }

        var lines: [Line] = []
        var points: [GeoPoint] = []
        for line in ordered {
            let straight = line.isStraightLine
            let coarse: [CLLocationCoordinate2D]
            let fine: [CLLocationCoordinate2D]
            if straight {
                let stops = ([line.from.geoPoint] + line.via.map(\.geoPoint) + [line.to.geoPoint]).filter(\.isValid)
                coarse = stops.map(\.coordinate)
                fine = coarse
            } else {
                coarse = line.coordinates(fine: false)
                fine = line.coordinates(fine: true)
            }
            guard coarse.count >= 2 else { continue }
            points += coarse.map { GeoPoint($0) }
            lines.append(Line(id: line.seq, code: line.code, colorHex: line.color,
                              coarse: coarse, fine: fine, straight: straight))
        }

        // Subida, transbordos y bajada: las estaciones del mapa; si aún no
        // están (mapa calculándose), las paradas de los tramos.
        var stops: [Stop] = []
        func color(zdc: String) -> String {
            ordered.first { $0.from.zdc == zdc || $0.to.zdc == zdc }?.color ?? ""
        }
        if !map.stations.isEmpty {
            for station in map.stations where station.geoPoint.isValid {
                stops.append(Stop(id: station.zdc, name: station.name, role: station.role,
                                  coordinate: station.coordinate, colorHex: color(zdc: station.zdc)))
            }
        } else {
            var seen: Set<String> = []
            for (index, line) in ordered.enumerated() {
                let boarding = line.from
                if boarding.geoPoint.isValid, seen.insert(boarding.zdc).inserted {
                    stops.append(Stop(id: boarding.zdc, name: boarding.name,
                                      role: index == 0 ? .origin : .transfer,
                                      coordinate: boarding.coordinate, colorHex: line.color))
                }
                if index == ordered.count - 1, line.to.geoPoint.isValid, seen.insert(line.to.zdc).inserted {
                    stops.append(Stop(id: line.to.zdc, name: line.to.name, role: .destination,
                                      coordinate: line.to.coordinate, colorHex: line.color))
                }
            }
        }
        points += stops.map { GeoPoint($0.coordinate) }

        var dots: [Dot] = []
        for line in ordered {
            for (index, via) in line.via.enumerated() where via.geoPoint.isValid {
                dots.append(Dot(id: "\(line.seq)-\(index)", name: via.name,
                                coordinate: via.coordinate, colorHex: line.color))
            }
        }

        var transfers: [Transfer] = []
        for transfer in map.transfers {
            let point = map.station(zdc: transfer.zdc)?.geoPoint
                ?? map.line(seq: transfer.fromSeq)?.to.geoPoint
            guard let point, point.isValid else { continue }
            transfers.append(Transfer(id: "\(transfer.zdc)-\(transfer.fromSeq)-\(transfer.toSeq)",
                                      coordinate: point.coordinate,
                                      label: TransferText.label(minTransferS: transfer.minTransferS)))
        }

        self.lines = lines
        self.stops = stops
        self.dots = dots
        self.transfers = transfers
        self.points = points
    }

    /// Cambia cuando cambia lo que se pinta.
    static func key(for map: RouteMap) -> String {
        "\(map.routeId)|\(map.generatedAt)|\(map.pending)|\(map.stale)|\(map.lines.count)|\(map.stations.count)|\(map.transfers.count)"
    }
}

// MARK: - Reglas del mapa (sin vista: se prueban solas)

enum RouteMapDetail {
    /// Por debajo de esta distancia de la cámara (m) se pinta la polilínea
    /// fina (simplificada a 2 m); por encima, la gruesa (20 m). Equivale a
    /// pasar de zoom 13 a 14 en un iPhone.
    static let fineBelowDistance: Double = 5_000
    /// Margen para no parpadear justo en el umbral.
    static let hysteresis: Double = 0.15

    static func useFine(cameraDistance: Double, current: Bool) -> Bool {
        guard cameraDistance.isFinite, cameraDistance > 0 else { return current }
        if current {
            return cameraDistance <= fineBelowDistance * (1 + hysteresis)
        }
        return cameraDistance < fineBelowDistance * (1 - hysteresis)
    }

    /// París, para cuando aún no hay nada que encuadrar.
    static var parisRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                           span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18))
    }

    /// El rectángulo que encuadra la ruta, con aire: más abajo que arriba,
    /// porque abajo va el panel (o el degradado de la cabecera del tablero).
    static func frame(points: [GeoPoint], style: RouteMapStyle) -> MKMapRect? {
        let valid = points.filter(\.isValid)
        guard !valid.isEmpty else { return nil }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for point in valid {
            let mapPoint = MKMapPoint(point.coordinate)
            minX = min(minX, mapPoint.x)
            maxX = max(maxX, mapPoint.x)
            minY = min(minY, mapPoint.y)
            maxY = max(maxY, mapPoint.y)
        }
        let latitude = valid.map(\.latitude).reduce(0, +) / Double(valid.count)
        let minimum = 800 * MKMapPointsPerMeterAtLatitude(latitude)     // nunca menos de 800 m
        let width = max(maxX - minX, minimum)
        let height = max(maxY - minY, minimum)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let sides = 0.15
        let top: Double = style == .header ? 0.25 : 0.35
        let bottom: Double = style == .header ? 0.9 : 1.0
        return MKMapRect(x: centerX - width / 2 - width * sides,
                         y: centerY - height / 2 - height * top,
                         width: width * (1 + 2 * sides),
                         height: height * (1 + top + bottom))
    }
}

/// Lo que se dice en un transbordo. Solo el tiempo mínimo: no hay camino
/// entre andenes en los datos abiertos (decisiones D1.7).
enum TransferText {
    static func label(minTransferS: Int?) -> String {
        guard let seconds = minTransferS, seconds > 0 else { return "Transbordo" }
        let minutes = max(1, Int((Double(seconds) / 60).rounded(.up)))
        return "Transbordo · mín. \(minutes) min"
    }
}
