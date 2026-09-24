import CoreLocation
import Foundation
import Observation
import UIKit

/// La ubicación, detrás de un protocolo para poder probar el modo trayecto
/// con una falsa.
///
/// Reglas (docs/app-v2.md «Modo trayecto»):
/// - El permiso se pide en el momento de usarlo («Empezar trayecto»), nunca
///   al abrir la app. «Siempre» solo al activar las geocercas en Ajustes.
/// - Ubicación en segundo plano SOLO mientras dura un trayecto, con precisión
///   de ~100 m.
@MainActor
protocol LocationService: AnyObject, Sendable {
    var authorization: LocationAuthorization { get }
    /// La última posición que se conoce (para el camino a pie del mapa).
    var lastLocation: TripLocation? { get }
    /// Se está siguiendo la ubicación de un trayecto.
    var isTracking: Bool { get }

    /// Cada posición nueva durante el trayecto.
    var onLocation: (@MainActor (TripLocation) -> Void)? { get set }
    /// El permiso ha cambiado (también desde Ajustes del sistema).
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)? { get set }

    /// «Al usar la app». Si ya se contestó, devuelve lo que hay sin preguntar.
    func requestWhenInUse() async -> LocationAuthorization
    /// «Siempre» (geocercas). Si ya se contestó, devuelve lo que hay.
    func requestAlways() async -> LocationAuthorization
    /// Empieza a seguir la ubicación del trayecto (también en segundo plano).
    func startTripUpdates()
    /// Deja de seguirla y apaga el segundo plano.
    func stopTripUpdates()
    /// Una posición suelta (el camino a pie del mapa), si hay permiso.
    func requestCurrentLocation()
}

/// La de verdad: `CLLocationManager`.
///
/// Durante el trayecto:
/// - `desiredAccuracy = kCLLocationAccuracyHundredMeters`: basta para saber
///   si se ha llegado a una estación (radio de ~150 m) y deja que iOS use
///   wifi y antenas en vez del GPS casi siempre.
/// - `distanceFilter = 50`: no despierta a la app por menos de 50 m.
/// - `pausesLocationUpdatesAutomatically = false`: una pausa automática
///   (tren parado en un túnel, andén) dejaría de despertar a la app y se
///   perdería la llegada; iOS no la reanuda sola en segundo plano. El gasto
///   ya lo acota el tiempo máximo del trayecto.
/// - `activityType = .otherNavigation` (tren).
/// - `allowsBackgroundLocationUpdates = true` solo mientras dura, y
///   `CLBackgroundActivitySession` (iOS 17) para que la app siga viva con el
///   permiso «Al usar la app». Al terminar, todo apagado.
@MainActor
@Observable
final class SystemLocationService: LocationService {

    private(set) var authorization: LocationAuthorization
    private(set) var lastLocation: TripLocation? = nil
    private(set) var isTracking = false

    @ObservationIgnored var onLocation: (@MainActor (TripLocation) -> Void)? = nil
    @ObservationIgnored var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)? = nil

    private let manager: CLLocationManager
    private let proxy: LocationDelegateProxy

    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession? = nil
    @ObservationIgnored private var waiters: [AuthorizationWaiter] = []
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)? = nil
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)? = nil
    @ObservationIgnored private var waitTimeout: Task<Void, Never>? = nil
    @ObservationIgnored private var promptCheck: Task<Void, Never>? = nil
    /// El aviso del sistema ha salido (la app ha dejado de estar activa).
    @ObservationIgnored private var promptShown = false

    /// Alguien espera la respuesta al aviso de permiso.
    private struct AuthorizationWaiter {
        let from: LocationAuthorization
        let continuation: CheckedContinuation<LocationAuthorization, Never>
    }

    private enum Ask {
        case whenInUse
        case always
    }

    init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.proxy = LocationDelegateProxy()
        self.authorization = LocationAuthorization(manager.authorizationStatus)
        proxy.owner = self
        manager.delegate = proxy
    }

    // MARK: - Permisos

    func requestWhenInUse() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await waitForAnswer(.whenInUse)
    }

    func requestAlways() async -> LocationAuthorization {
        switch authorization {
        case .always, .denied:
            return authorization
        case .notDetermined, .whenInUse:
            return await waitForAnswer(.always)
        }
    }

    /// Pregunta y espera: a que cambie el permiso, a que la app vuelva a
    /// estar activa (el aviso se ha cerrado; al pasar de «Al usar» a
    /// «Siempre» iOS no avisa si se queda igual) o, como mucho, 90 s. Si el
    /// aviso ni siquiera sale (iOS pregunta «Siempre» una sola vez en la vida
    /// de la app), se contesta enseguida con lo que hay.
    private func waitForAnswer(_ ask: Ask) async -> LocationAuthorization {
        let from = authorization
        return await withCheckedContinuation { continuation in
            waiters.append(AuthorizationWaiter(from: from, continuation: continuation))
            watchForAnswer()
            switch ask {
            case .whenInUse: manager.requestWhenInUseAuthorization()
            case .always: manager.requestAlwaysAuthorization()
            }
        }
    }

    private func watchForAnswer() {
        promptShown = false
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // Cola principal: ya se está en el MainActor.
                MainActor.assumeIsolated {
                    self?.promptShown = true
                }
            }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Deja llegar antes el aviso del cambio de permiso.
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.resumeAllWaiters()
                }
            }
        }
        promptCheck?.cancel()
        promptCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, !self.promptShown else { return }
            self.resumeAllWaiters()
        }
        waitTimeout?.cancel()
        waitTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.resumeAllWaiters()
        }
    }

    private func resumeAllWaiters() {
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.continuation.resume(returning: authorization)
        }
        stopWatchingIfIdle()
    }

    private func resumeAnswered() {
        let current = authorization
        let answered = waiters.filter { $0.from != current }
        waiters.removeAll { $0.from != current }
        for waiter in answered {
            waiter.continuation.resume(returning: current)
        }
        stopWatchingIfIdle()
    }

    private func stopWatchingIfIdle() {
        guard waiters.isEmpty else { return }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        activeObserver = nil
        resignObserver = nil
        waitTimeout?.cancel()
        waitTimeout = nil
        promptCheck?.cancel()
        promptCheck = nil
    }

    // MARK: - Trayecto

    func startTripUpdates() {
        guard !isTracking else { return }
        isTracking = true
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        if Self.declaresBackgroundLocation {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        // Mantiene la app viva en segundo plano con «Al usar la app» (iOS 17).
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
    }

    func stopTripUpdates() {
        guard isTracking else { return }
        isTracking = false
        manager.stopUpdatingLocation()
        if Self.declaresBackgroundLocation {
            manager.allowsBackgroundLocationUpdates = false
        }
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    func requestCurrentLocation() {
        guard authorization.allowsTrip, !isTracking else { return }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
    }

    /// Poner `allowsBackgroundLocationUpdates` sin el modo `location` en
    /// UIBackgroundModes tumba la app: se mira antes.
    private static var declaresBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    // MARK: - Lo que dice el delegado

    fileprivate func didUpdate(_ fixes: [TripLocation]) {
        guard let last = fixes.last else { return }
        lastLocation = last
        onLocation?(last)
    }

    fileprivate func didChangeAuthorization(_ status: LocationAuthorization) {
        let changed = status != authorization
        authorization = status
        resumeAnswered()
        if changed {
            onAuthorizationChange?(status)
        }
    }
}

/// El delegado de CoreLocation. CLLocationManager llama en el hilo donde se
/// creó (el principal, porque lo crea `SystemLocationService`, que es del
/// MainActor): se pasa a valores `Sendable` y se entra en el MainActor sin
/// saltos.
@MainActor
private final class LocationDelegateProxy: NSObject, CLLocationManagerDelegate {
    weak var owner: SystemLocationService?

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { TripLocation($0) }
        MainActor.assumeIsolated {
            self.owner?.didUpdate(fixes)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Sin posición (interior, sin permiso): el trayecto sigue sin ella.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = LocationAuthorization(manager.authorizationStatus)
        MainActor.assumeIsolated {
            self.owner?.didChangeAuthorization(status)
        }
    }
}

// MARK: - Demo

#if DEBUG
/// Ubicación de mentira para la demo (`-demo`) y los tests de interfaz: con
/// permiso y en la calle de Amsterdam, a unos 250 m de Saint-Lazare. No pide
/// nada al sistema.
///
/// Con `-demoSinUbicacion` el permiso está sin contestar y, al pedirlo, se
/// deniega: sirve para probar que el trayecto sigue sin GPS.
@MainActor
@Observable
final class DemoLocationService: LocationService {
    nonisolated static let spot = GeoPoint(latitude: 48.87895, longitude: 2.32675)

    private(set) var authorization: LocationAuthorization
    private(set) var lastLocation: TripLocation? = nil
    private(set) var isTracking = false
    @ObservationIgnored var onLocation: (@MainActor (TripLocation) -> Void)? = nil
    @ObservationIgnored var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)? = nil

    init(withoutPermission: Bool = ProcessInfo.processInfo.arguments.contains("-demoSinUbicacion")) {
        authorization = withoutPermission ? .notDetermined : .whenInUse
    }

    func requestWhenInUse() async -> LocationAuthorization {
        deny()
        return authorization
    }

    func requestAlways() async -> LocationAuthorization {
        deny()
        return authorization
    }

    /// Sin permiso, la respuesta a la pregunta es «no».
    private func deny() {
        guard authorization == .notDetermined else { return }
        authorization = .denied
        onAuthorizationChange?(.denied)
    }

    func startTripUpdates() {
        isTracking = true
        publish()
    }

    func stopTripUpdates() {
        isTracking = false
    }

    func requestCurrentLocation() {
        publish()
    }

    private func publish() {
        let fix = TripLocation(point: Self.spot, horizontalAccuracy: 65, timestamp: Date())
        lastLocation = fix
        if isTracking { onLocation?(fix) }
    }
}
#endif
