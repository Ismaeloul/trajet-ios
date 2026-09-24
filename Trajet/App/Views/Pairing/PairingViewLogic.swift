import AVFoundation
import Foundation

// Lógica del emparejamiento que NO es vista (docs/arquitectura.md §4,
// sistema.md §7.17): qué hacer con un QR leído, el formulario a mano, en qué
// estado está la pantalla y qué se dice en cada fallo. Funciones puras para
// probarlas sin cámara (TrajetTests/PairingViewLogicTests.swift). El
// emparejamiento en sí lo hace `PairingStore` (ping en cada dirección, canje
// del código, token al Llavero).

// MARK: - Cámara

/// El permiso de la cámara, más «no hay cámara» (el simulador).
enum CameraPermission: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable

    init(_ status: AVAuthorizationStatus, hasCamera: Bool) {
        guard hasCamera else {
            self = .unavailable
            return
        }
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    /// El de ahora.
    static func current() -> CameraPermission {
        CameraPermission(AVCaptureDevice.authorizationStatus(for: .video),
                         hasCamera: AVCaptureDevice.default(for: .video) != nil)
    }

    /// Se puede pedir (o ya está dado).
    var canScan: Bool { self == .authorized || self == .notDetermined }
}

// MARK: - Qué hacer con un QR leído

enum PairingScanDecision: Equatable, Sendable {
    /// Un enlace `trajet://pair?…`: se empareja con él.
    case pair(URL)
    /// Otro enlace de Trajet (una ruta, el tablero…): no sirve para emparejar.
    case otherTrajetLink
    /// Un QR que no es de Trajet: se sigue buscando.
    case notTrajet

    static func decide(_ payload: String) -> PairingScanDecision {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let link = AppLink(url: url) else { return .notTrajet }
        if case .pair = link { return .pair(url) }
        return .otherTrajetLink
    }

    /// Lo que se dice sin parar de buscar (nil si se empareja).
    var hint: String? {
        switch self {
        case .pair: nil
        case .otherTrajetLink: "Ese QR es de Trajet, pero no es el de emparejar. Genera uno en el panel del servidor."
        case .notTrajet: "Ese QR no es de Trajet. Enfoca el del panel del servidor."
        }
    }
}

// MARK: - Formulario a mano

/// El código y las direcciones escritos a mano (sistema.md §7.17, A28).
struct ManualPairingInput: Equatable, Sendable {
    var code: String = ""
    var lan: String = ""
    var tailscale: String = ""

    init(code: String = "", lan: String = "", tailscale: String = "") {
        self.code = code
        self.lan = lan
        self.tailscale = tailscale
    }

    /// El código como lo quiere el servidor («ABCD-EFGH»), o nil si no vale.
    /// Se aceptan minúsculas, espacios y sin guion.
    var normalizedCode: String? {
        try? PairingLink.normalizeCode(code)
    }

    /// Lo que falla del código (nil si vale o si aún no se ha escrito nada).
    var codeProblem: String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, normalizedCode == nil else { return nil }
        return PairingLinkError.badCode.errorDescription
    }

    /// La dirección de casa normalizada; nil si está vacía o no vale.
    var lanURL: String? { ServerConfig.normalize(lan) }
    var tailscaleURL: String? { ServerConfig.normalize(tailscale) }

    var lanProblem: String? { Self.addressProblem(lan) }
    var tailscaleProblem: String? { Self.addressProblem(tailscale) }

    /// Una dirección escrita que no se entiende o que iOS no dejará usar.
    static func addressProblem(_ raw: String) -> String? {
        let kind = ServerAddressRules.classify(raw)
        switch kind {
        case .invalid, .needsHTTPS: return ServerAddressRules.note(kind)
        case .empty, .https, .localNetwork, .tailscaleIP, .magicDNS, .other: return nil
        }
    }

    /// Se puede intentar: código bueno, las direcciones escritas se
    /// entienden y hay al menos una (escrita o guardada de antes).
    func canSubmit(hasSavedAddresses: Bool) -> Bool {
        guard normalizedCode != nil else { return false }
        let lanTyped = !lan.trimmingCharacters(in: .whitespaces).isEmpty
        let tsTyped = !tailscale.trimmingCharacters(in: .whitespaces).isEmpty
        if lanTyped, lanURL == nil { return false }
        if tsTyped, tailscaleURL == nil { return false }
        return lanURL != nil || tailscaleURL != nil || hasSavedAddresses
    }

    /// Las direcciones escritas, en el orden en que se prueban (casa,
    /// Tailscale).
    var typedAddresses: [String] { [lanURL, tailscaleURL].compactMap { $0 } }
}

// MARK: - En qué punto está la pantalla

/// Lo que enseña la pantalla de emparejar.
enum PairingStage: Equatable, Sendable {
    /// Antes de abrir la cámara: qué hace falta y los dos caminos.
    case intro
    /// La cámara, buscando el QR.
    case scanning
    /// QR leído o código enviado: probando direcciones y canjeando.
    case connecting
    /// Emparejado (solo se ve si la pantalla sigue delante: al emparejar de
    /// nuevo desde Ajustes).
    case paired
    case failed(PairingFailure)
    case cameraDenied
    case cameraUnavailable

    static func make(phase: PairingStore.Phase, wantsCamera: Bool, camera: CameraPermission,
                     didPair: Bool) -> PairingStage {
        switch phase {
        case .checking, .pairing:
            return .connecting
        case .failed(let failure):
            return .failed(failure)
        case .idle:
            if didPair { return .paired }
            guard wantsCamera else { return .intro }
            switch camera {
            case .authorized, .notDetermined: return .scanning
            case .denied, .restricted: return .cameraDenied
            case .unavailable: return .cameraUnavailable
            }
        }
    }

    /// El marco del escáner se encoge y se pone verde.
    var frameFound: Bool {
        switch self {
        case .connecting, .paired: true
        case .intro, .scanning, .failed, .cameraDenied, .cameraUnavailable: false
        }
    }

    /// Se ve la cámara detrás.
    var showsCamera: Bool {
        switch self {
        case .scanning, .connecting: true
        case .intro, .paired, .failed, .cameraDenied, .cameraUnavailable: false
        }
    }
}

// MARK: - Textos

/// Qué se ofrece hacer tras un fallo.
enum PairingAction: Equatable, Sendable {
    case scanAgain
    case typeManually
    case openSettings
}

/// Lo que se dice en cada estado (sistema.md §7.17).
struct PairingCopy: Equatable, Sendable {
    var title: String
    var message: String
    var hint: String?
    var actions: [PairingAction]
}

enum PairingText {
    static let intro = PairingCopy(
        title: "Emparejar con el servidor",
        message: "Abre el panel de Trajet en tu Umbrel, toca «Emparejar un iPhone» y escanea el QR. El código dura 5 minutos.",
        hint: nil, actions: [])

    static let scanning = "Enfoca el QR del panel del servidor."

    static func connecting(serverName: String?) -> String {
        let name = (serverName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Conectando con el servidor…" : "Conectando con «\(name)»…"
    }

    /// «Listo. iPhone de Isma emparejado.»
    static func paired(deviceName: String?) -> String {
        let name = (deviceName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Listo. Este iPhone ya está emparejado." : "Listo. \(name) emparejado."
    }

    static let cameraDenied = PairingCopy(
        title: "Sin permiso de cámara",
        message: "Trajet necesita la cámara para leer el QR. Puedes darle permiso en Ajustes o escribir el código a mano.",
        hint: nil, actions: [.openSettings, .typeManually])

    static let cameraUnavailable = PairingCopy(
        title: "No hay cámara",
        message: "Este dispositivo no tiene una cámara que se pueda usar. Escribe el código y la dirección a mano.",
        hint: nil, actions: [.typeManually])

    /// El texto de «Demasiados intentos» con el tiempo de espera.
    static func wait(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Espera un poco y vuelve a probar." }
        if seconds < 60 { return "Prueba dentro de \(seconds) s." }
        let minutes = (seconds + 59) / 60
        return "Prueba dentro de \(minutes) min."
    }

    /// Qué se dice cuando falla (A28: diseñado, no un error genérico).
    /// `addresses` son las direcciones que se han probado, para dar la pista
    /// buena (red local, ATS, Tailscale).
    static func failure(_ failure: PairingFailure, addresses: [String]) -> PairingCopy {
        switch failure {
        case .codeRejected:
            // El servidor no distingue malo, caducado o usado (R86).
            return PairingCopy(title: "Ese código ya no vale",
                               message: "Genera otro en el panel del servidor: cada código dura 5 minutos y solo sirve una vez.",
                               hint: nil, actions: [.scanAgain, .typeManually])
        case .rateLimited(let retry):
            return PairingCopy(title: "Demasiados intentos", message: wait(retry),
                               hint: "Es una protección del servidor contra quien prueba códigos a ciegas.",
                               actions: [.scanAgain])
        case .unreachable(let detail):
            return PairingCopy(title: "No encuentro el servidor",
                               message: detail.isEmpty ? "No responde en ninguna de sus direcciones." : detail,
                               hint: networkHint(addresses: addresses, detail: detail),
                               actions: [.scanAgain, .typeManually])
        case .notTrajet:
            return PairingCopy(title: "Ahí no hay un Trajet",
                               message: "En esa dirección responde algo, pero no es el servidor de Trajet. Revisa la dirección y el puerto (7796).",
                               hint: nil, actions: [.typeManually, .scanAgain])
        case .invalidLink(let error):
            return PairingCopy(title: "Ese QR no vale",
                               message: error.errorDescription ?? "El QR no se entiende.",
                               hint: nil, actions: [.scanAgain, .typeManually])
        case .keychain:
            return PairingCopy(title: "No se ha podido guardar la llave",
                               message: "El servidor ha aceptado el código, pero el iPhone no ha podido guardar la llave. Genera otro código y vuelve a probar.",
                               hint: nil, actions: [.scanAgain, .typeManually])
        case .server(let detail):
            return PairingCopy(title: "El servidor ha dado un error",
                               message: detail.isEmpty ? "Vuelve a probar dentro de un rato." : detail,
                               hint: nil, actions: [.scanAgain, .typeManually])
        }
    }

    /// La pista cuando no se llega: ATS (iOS corta HTTP a direcciones que no
    /// son locales ni de Tailscale), red local (R45) y Tailscale.
    static func networkHint(addresses: [String], detail: String) -> String? {
        let kinds = addresses.map(ServerAddressRules.classify)
        if detail.contains("HTTPS") || kinds.contains(.needsHTTPS) {
            return "iOS no deja usar por HTTP direcciones que no sean de casa o de Tailscale (100.x o *.ts.net)."
        }
        var tips: [String] = []
        if kinds.contains(.localNetwork) {
            tips.append("Para la red de casa, el iPhone tiene que estar en esa wifi y Trajet con permiso de red local (Ajustes › Privacidad y seguridad › Red local).")
        }
        if kinds.contains(.tailscaleIP) || kinds.contains(.magicDNS) {
            tips.append("Para Tailscale, que esté encendido en el iPhone.")
        }
        return tips.isEmpty ? nil : tips.joined(separator: " ")
    }

    static func actionTitle(_ action: PairingAction) -> String {
        switch action {
        case .scanAgain: "Volver a escanear"
        case .typeManually: "Escribir a mano"
        case .openSettings: "Abrir Ajustes"
        }
    }
}
