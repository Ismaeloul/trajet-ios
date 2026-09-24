import AVFoundation
import SwiftUI
import UIKit

/// La cámara leyendo códigos QR (AVFoundation): `AVCaptureSession` +
/// `AVCaptureMetadataOutput` con `.qr`, dentro de un
/// `UIViewControllerRepresentable`.
///
/// - La sesión se configura, arranca y para FUERA del hilo principal, en su
///   propia cola (`startRunning` bloquea).
/// - Cada QR se entrega una vez (el mismo texto no se repite en 3 s) y en el
///   hilo principal.
/// - `isPaused` para la cámara (mientras se conecta, o si la pantalla deja
///   de estar delante); se vuelve a encender al quitarlo.
/// - Si no hay cámara o no se puede abrir, se avisa con `onUnavailable`.
///
/// El permiso lo pide quien la enseña, antes y con una explicación.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void
    var isPaused: Bool = false
    var onUnavailable: (@MainActor () -> Void)?

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        controller.setPaused(isPaused)
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        controller.setPaused(isPaused)
    }

    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) {
        controller.shutDown()
    }
}

/// El controlador de la cámara. Vive en el hilo principal; la sesión, en su
/// cola (`QRCaptureSession`).
final class QRScannerController: UIViewController {
    var onCode: (@MainActor (String) -> Void)?
    var onUnavailable: (@MainActor () -> Void)?

    private let capture = QRCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var paused = false
    private var visible = false
    private var lastCode: String?
    private var lastCodeAt = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: capture.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        let sink = QRMetadataSink { [weak self] code in
            Task { @MainActor in
                self?.received(code)
            }
        }
        capture.configure(sink: sink) { [weak self] ready in
            Task { @MainActor in
                self?.configured(ready)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        updateRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        updateRunning()
    }

    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        if !paused {
            // Al volver a buscar, el mismo QR vale otra vez.
            lastCode = nil
        }
        updateRunning()
    }

    /// Para del todo (la vista se va).
    func shutDown() {
        visible = false
        capture.stop()
    }

    private func updateRunning() {
        if visible && !paused {
            capture.start()
        } else {
            capture.stop()
        }
    }

    private func configured(_ ready: Bool) {
        if ready {
            updateRunning()
        } else {
            onUnavailable?()
        }
    }

    private func received(_ code: String) {
        guard !paused else { return }
        let now = Date()
        if code == lastCode, now.timeIntervalSince(lastCodeAt) < 3 { return }
        lastCode = code
        lastCodeAt = now
        onCode?(code)
    }
}

/// La sesión de captura y su cola. Todo lo que toca la sesión (configurar,
/// arrancar, parar) pasa en `queue`, fuera del hilo principal; por eso es
/// `@unchecked Sendable`: la cola serie es la que protege el estado.
final class QRCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.ismaeloul.trajet.qr-camera")
    // Solo en `queue`.
    private var isConfigured = false
    private var sink: QRMetadataSink?

    /// Prepara la cámara trasera y la salida de QR. `done(true)` si está
    /// lista; `done(false)` si no hay cámara o no se puede abrir.
    func configure(sink: QRMetadataSink, done: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard !self.isConfigured else {
                done(true)
                return
            }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                done(false)
                return
            }
            let output = AVCaptureMetadataOutput()
            self.session.beginConfiguration()
            guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                done(false)
                return
            }
            self.session.addInput(input)
            self.session.addOutput(output)
            // El delegado se llama en el hilo principal; el sink lo pasa al
            // controlador.
            output.setMetadataObjectsDelegate(sink, queue: DispatchQueue.main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
            self.session.commitConfiguration()
            self.sink = sink
            self.isConfigured = true
            done(true)
        }
    }

    func start() {
        queue.async { [self] in
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

/// Recibe lo que lee la cámara y entrega el texto del primer QR.
///
/// TODO-COMPILAR: se da por hecho que `AVCaptureMetadataOutputObjectsDelegate`
/// no está aislado a ningún actor (el delegado se llama en la cola que se le
/// da, aquí la principal). Si Swift 6 pide aislamiento, marcar el método
/// `nonisolated` (ya lo es: la clase no es del MainActor).
final class QRMetadataSink: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    private let onCode: @Sendable (String) -> Void

    init(onCode: @escaping @Sendable (String) -> Void) {
        self.onCode = onCode
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  code.type == .qr,
                  let text = code.stringValue, !text.isEmpty
            else { continue }
            onCode(text)
            return
        }
    }
}
