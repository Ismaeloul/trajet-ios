import Foundation
import Observation
import UIKit

/// El contenido del QR del panel (`PairingQR` del contrato):
/// `trajet://pair?v=1&code=ABCD-EFGH&lan=<url>&ts=<url>&name=<nombre>`.
/// `lan` y `ts` van con percent-encoding y puede faltar una de las dos.
struct PairingLink: Hashable, Sendable {
    var code: String              // normalizado: mayúsculas, sin espacios
    var lanURL: String?
    var tailscaleURL: String?
    var serverName: String?

    /// Las direcciones en el orden en que se prueban: casa, Tailscale.
    var addresses: [String] { [lanURL, tailscaleURL].compactMap { $0 } }

    /// Lee un enlace del QR. Tira un `PairingLinkError` que se puede enseñar.
    static func parse(_ url: URL) throws -> PairingLink {
        guard url.scheme?.lowercased() == AppLink.scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host?.lowercased() == "pair"
        else { throw PairingLinkError.notAPairingLink }

        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            let raw = items.first(where: { $0.name == name })?.value ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        if let version = value("v"), version != "1" {
            throw PairingLinkError.unsupportedVersion(version)
        }
        guard let rawCode = value("code") else { throw PairingLinkError.missingCode }
        let code = try normalizeCode(rawCode)

        var lan: String?
        var ts: String?
        if let raw = value("lan") {
            guard let url = ServerConfig.normalize(raw) else { throw PairingLinkError.badAddress(raw) }
            lan = url
        }
        if let raw = value("ts") {
            guard let url = ServerConfig.normalize(raw) else { throw PairingLinkError.badAddress(raw) }
            ts = url
        }
        guard lan != nil || ts != nil else { throw PairingLinkError.noAddresses }
        return PairingLink(code: code, lanURL: lan, tailscaleURL: ts, serverName: value("name"))
    }

    /// El código tal como lo escribe una persona: «abcd efgh», «ABCD-EFGH»…
    /// Se aceptan minúsculas, espacios y sin guion; de 8 a 16 caracteres.
    static func normalizeCode(_ raw: String) throws -> String {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace }
        let allowed = cleaned.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let letters = cleaned.filter { $0 != "-" }.count
        guard allowed, (8...16).contains(cleaned.count), letters >= 8 else {
            throw PairingLinkError.badCode
        }
        return cleaned
    }
}

/// Por qué no vale un enlace de emparejamiento.
enum PairingLinkError: Error, Equatable, Sendable, LocalizedError {
    case notAPairingLink
    case unsupportedVersion(String)
    case missingCode
    case badCode
    case noAddresses
    case badAddress(String)

    var errorDescription: String? {
        switch self {
        case .notAPairingLink: "Ese código no es de Trajet."
        case .unsupportedVersion(let v): "El QR es de una versión nueva (v\(v)). Actualiza la app."
        case .missingCode: "Al QR le falta el código."
        case .badCode: "El código no tiene buena pinta: son 8 letras y números, como ABCD-EFGH."
        case .noAddresses: "El QR no trae ninguna dirección del servidor. Ponlas en el panel."
        case .badAddress(let a): "La dirección «\(a)» no es válida."
        }
    }
}

/// Por qué no se ha podido emparejar.
enum PairingFailure: Equatable, Sendable {
    case invalidLink(PairingLinkError)
    /// Ninguna dirección responde (o no hay ninguna).
    case unreachable(String)
    /// Responde algo, pero no es un Trajet.
    case notTrajet
    /// Código mal escrito, caducado o ya usado (el servidor no distingue).
    case codeRejected
    /// Demasiados intentos: esperar.
    case rateLimited(retryAfter: Int?)
    /// Se emparejó, pero el token no se pudo guardar en el Llavero.
    case keychain
    case server(String)

    var message: String {
        switch self {
        case .invalidLink(let e): return e.errorDescription ?? "El QR no vale."
        case .unreachable(let detail): return detail
        case .notTrajet: return "En esa dirección responde algo, pero no es Trajet."
        case .codeRejected: return "El código no vale: puede que esté mal escrito, que haya caducado (duran 5 minutos) o que ya se haya usado. Genera otro en el panel."
        case .rateLimited(let retry):
            if let retry { return "Demasiados intentos. Vuelve a probar en \(retry) s." }
            return "Demasiados intentos. Espera un poco."
        case .keychain: return "No se ha podido guardar la llave en el iPhone."
        case .server(let detail): return detail
        }
    }
}

/// Emparejar este iPhone con el servidor.
///
/// Con el QR (o el enlace `trajet://pair?…` que abre la cámara del sistema):
/// se prueban sus direcciones con `ping` en orden, se canjea el código en la
/// que responde y se guardan el token (Llavero) y las direcciones
/// (`ServerConfig`). A mano: el código y, si hace falta, las direcciones.
@MainActor
@Observable
final class PairingStore {

    enum Phase: Equatable, Sendable {
        case idle
        /// Probando las direcciones.
        case checking
        /// Canjeando el código.
        case pairing
        case failed(PairingFailure)
    }

    private(set) var phase: Phase = .idle
    /// Hay token en el Llavero.
    private(set) var isPaired: Bool
    /// Este iPhone según el servidor (tras emparejar o `refreshDevice()`).
    private(set) var device: DeviceInfo?
    /// El último enlace leído (para enseñar a qué servidor se va a emparejar).
    private(set) var lastLink: PairingLink?

    /// Tras emparejar y tras desemparejar (lo conecta `AppServices`).
    @ObservationIgnored var onPaired: (@MainActor () -> Void)?
    @ObservationIgnored var onUnpaired: (@MainActor () -> Void)?

    private let api: TrajetAPI
    private let config: ServerConfig
    private let tokens: TokenStore

    init(api: TrajetAPI, config: ServerConfig, tokens: TokenStore) {
        self.api = api
        self.config = config
        self.tokens = tokens
        self.isPaired = tokens.read() != nil
    }

    var isBusy: Bool { phase == .checking || phase == .pairing }

    var serverName: String { config.serverName }

    var failure: PairingFailure? {
        if case .failed(let f) = phase { return f }
        return nil
    }

    /// Un enlace `trajet://pair?…` (onOpenURL o el escáner). true si emparejó.
    @discardableResult
    func handle(url: URL) async -> Bool {
        do {
            let link = try PairingLink.parse(url)
            return await pair(link: link)
        } catch let error as PairingLinkError {
            phase = .failed(.invalidLink(error))
            return false
        } catch {
            phase = .failed(.invalidLink(.notAPairingLink))
            return false
        }
    }

    /// Lo leído de un QR.
    @discardableResult
    func pair(link: PairingLink) async -> Bool {
        lastLink = link
        return await pair(code: link.code, addresses: link.addresses, serverName: link.serverName,
                          qrLAN: link.lanURL, qrTailscale: link.tailscaleURL)
    }

    /// A mano: el código y las direcciones que se escriban. Sin direcciones,
    /// las que ya tenga `ServerConfig`.
    @discardableResult
    func pair(code: String, lanURL: String? = nil, tailscaleURL: String? = nil) async -> Bool {
        let normalized: String
        do {
            normalized = try PairingLink.normalizeCode(code)
        } catch {
            phase = .failed(.invalidLink(.badCode))
            return false
        }
        let lan = lanURL.flatMap(ServerConfig.normalize)
        let ts = tailscaleURL.flatMap(ServerConfig.normalize)
        let typed = [lan, ts].compactMap { $0 }
        let addresses = typed.isEmpty ? config.candidates : typed
        return await pair(code: normalized, addresses: addresses, serverName: nil,
                          qrLAN: lan, qrTailscale: ts)
    }

    private func pair(code: String, addresses: [String], serverName: String?,
                      qrLAN: String?, qrTailscale: String?) async -> Bool {
        guard !isBusy else { return false }
        guard !addresses.isEmpty else {
            phase = .failed(.unreachable("No hay ninguna dirección del servidor a la que llamar."))
            return false
        }

        // 1. ¿Cuál responde? (casa primero, luego Tailscale)
        phase = .checking
        var reachable: String?
        var sawSomethingElse = false
        for address in addresses {
            do {
                let ping = try await api.ping(baseURL: address)
                if ping.isTrajet {
                    reachable = address
                    break
                }
                sawSomethingElse = true
            } catch is CancellationError {
                phase = .idle
                return false
            } catch let error as APIError {
                if !error.isNetwork { sawSomethingElse = true }
            } catch {
                continue
            }
        }
        guard let reachable else {
            phase = .failed(sawSomethingElse
                            ? .notTrajet
                            : .unreachable(addresses.count > 1
                                           ? "No se llega al servidor ni por la red de casa ni por Tailscale. ¿Estás en la misma red o con Tailscale encendido?"
                                           : "No se llega al servidor en esa dirección."))
            return false
        }

        // 2. Canjear el código.
        phase = .pairing
        let request = PairRequest(code: code, deviceName: Self.deviceName(),
                                  deviceModel: Self.deviceModel(), appVersion: Self.appVersion())
        let result: PairResult
        do {
            result = try await api.pair(request, baseURL: reachable)
        } catch is CancellationError {
            phase = .idle
            return false
        } catch let error as APIError {
            phase = .failed(Self.failure(for: error))
            return false
        } catch {
            phase = .failed(.server(error.localizedDescription))
            return false
        }

        // 3. Guardar token y direcciones. Las del servidor mandan; si no
        //    trae alguna, la del QR.
        guard !result.token.isEmpty, tokens.save(result.token) else {
            phase = .failed(.keychain)
            return false
        }
        config.applyPairing(lan: result.server.url(.lan) ?? qrLAN,
                            tailscale: result.server.url(.tailscale) ?? qrTailscale,
                            name: result.server.name.isEmpty ? serverName : result.server.name,
                            reachable: reachable)
        await api.clearETags()
        device = result.device
        isPaired = true
        phase = .idle
        onPaired?()
        return true
    }

    /// Pide al servidor los datos de este iPhone.
    func refreshDevice() async {
        guard isPaired else { return }
        if let me = try? await api.me() { device = me }
    }

    /// Desemparejar: se pide al servidor que revoque el token (si no se llega,
    /// da igual) y se olvida todo en el iPhone.
    func unpair() async {
        _ = try? await api.unpair()
        forgetLocally()
    }

    /// Olvida el emparejamiento sin hablar con el servidor (token revocado
    /// desde el panel, 401).
    func forgetLocally() {
        tokens.delete()
        config.clearAll()
        device = nil
        lastLink = nil
        isPaired = false
        phase = .idle
        onUnpaired?()
    }

    /// Vuelve al estado inicial tras enseñar un fallo.
    func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }

    nonisolated static func failure(for error: APIError) -> PairingFailure {
        switch error {
        case .network(let message):
            return .unreachable(message)
        case .server(let code, let message, _, let retryAfter):
            switch ServerErrorCode(code: code) {
            case .pairingInvalid: return .codeRejected
            case .rateLimited: return .rateLimited(retryAfter: retryAfter)
            default: return .server(error.errorDescription ?? message)
            }
        case .unauthorized:
            return .codeRejected
        case .notFound:
            return .notTrajet
        case .notPaired, .decoding:
            return .server(error.errorDescription ?? "")
        }
    }

    // MARK: - Este iPhone

    private static func deviceName() -> String {
        let name = UIDevice.current.name
        return name.isEmpty ? "iPhone" : name
    }

    private static func deviceModel() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            return sim
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }

    private static func appVersion() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
