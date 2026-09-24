import AVFoundation
import SwiftUI
import UIKit

/// Emparejar este iPhone con el servidor (docs/arquitectura.md §4,
/// sistema.md §7.17). Es la primera pantalla mientras no hay emparejamiento
/// (`RootView`) y la que se abre con «Emparejar de nuevo» en Ajustes.
///
/// - Dos caminos: escanear el QR del panel con la cámara (AVFoundation,
///   `QRScannerView`) o escribir el código y las direcciones a mano
///   (`ManualPairingView`).
/// - El permiso de cámara se pide al tocar «Escanear», con la explicación
///   delante; si se deniega, «Abrir Ajustes» y el camino a mano.
/// - Estados: buscando (el marco respira) → conectando (el marco se encoge y
///   se pone verde) → emparejado, o un error DISEÑADO: código que no vale o
///   caducado, demasiados intentos (con la espera), servidor que no aparece
///   en ninguna dirección (con la pista de red local, Tailscale o ATS).
/// - El enlace `trajet://pair?…` abierto con la cámara del sistema llega por
///   `AppServices.handle(url:)` a `services.pairing`, y esta pantalla enseña
///   su progreso igual.
///
/// Siempre oscura, como en B. Con «Reducir movimiento» el marco no respira
/// ni se encoge: cambia de color.
struct PairingFlowView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var wantsCamera = false
    @State private var camera: CameraPermission = .notDetermined
    @State private var scanHint: String?
    @State private var showingManual = false
    @State private var didPair = false
    /// Las direcciones del último intento, para la pista cuando no se llega.
    @State private var triedAddresses: [String] = []

    private var stage: PairingStage {
        PairingStage.make(phase: services.pairing.phase, wantsCamera: wantsCamera, camera: camera, didPair: didPair)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: Metrics.Space.l) {
                header
                Spacer(minLength: Metrics.Space.l)
                if stage.showsCamera || stage == .intro || stage == .paired {
                    scannerFrame
                        .accessibilityHidden(true)
                }
                Spacer(minLength: Metrics.Space.l)
                panel
            }
            .padding(.horizontal, Metrics.Space.gutter)
            .padding(.bottom, Metrics.Space.gutter)
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingManual) {
            ManualPairingView {
                showingManual = false
                succeeded()
            }
            .environment(services)
        }
        .onAppear {
            camera = CameraPermission.current()
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver de Ajustes con el permiso cambiado.
            if phase == .active { camera = CameraPermission.current() }
        }
        .onChange(of: services.pairing.phase) { old, new in
            // Sirve también para el enlace de la cámara del sistema.
            let wasBusy = old == .checking || old == .pairing
            if wasBusy, new == .idle, services.pairing.isPaired {
                succeeded()
            }
        }
    }

    // MARK: - Fondo y marco

    @ViewBuilder
    private var background: some View {
        if stage.showsCamera, wantsCamera, camera == .authorized {
            QRScannerView(onCode: { scanned($0) },
                          isPaused: stage != .scanning,
                          onUnavailable: { camera = .unavailable })
                .ignoresSafeArea()
                .overlay(Color.black.opacity(stage == .scanning ? 0.15 : 0.45).ignoresSafeArea())
        } else {
            RadialGradient(colors: [Tokens.surfaceHi.color(for: .dark), Tokens.bg.color(for: .dark)],
                           center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var scannerFrame: some View {
        let found = stage.frameFound
        let ring = RoundedRectangle(cornerRadius: 40, style: .continuous)
            .stroke(found ? Palette.okText : Color.white.opacity(0.5), lineWidth: 3)
            .frame(width: 240, height: 240)
            .overlay {
                if stage == .paired {
                    Image(systemName: "checkmark")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Palette.okText)
                } else if stage == .intro {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
        if stage == .scanning && !reduceMotion {
            // Respira (escala 1 ↔ 1,05 en 1,2 s) mientras busca.
            // TODO-COMPILAR: `phaseAnimator(_:content:animation:)` (iOS 17).
            // Si no casa, `.scaleEffect(1)` sin respirar: solo se pierde el
            // latido del marco.
            ring.phaseAnimator([1.0, 1.05]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .easeInOut(duration: Motion.Timing.breathe)
            }
        } else {
            ring
                .scaleEffect(found && !reduceMotion ? 0.85 : 1)
                .animation(Motion.animation(.pairFound, reduceMotion: reduceMotion), value: found)
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Trajet")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Tu tablero de trenes, desde tu servidor")
                    .textLevel(.callout)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
            if isPresented {
                Button("Cancelar") { dismiss() }
                    .cristalButton()
                    .disabled(stage == .connecting)
            }
        }
        .padding(.top, Metrics.Space.l)
    }

    // MARK: - Panel de cristal

    private var panel: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.ml) {
            panelContent
        }
        .padding(Metrics.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cristal(.panel)
        .animation(Motion.animation(.ease, reduceMotion: reduceMotion), value: stage)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch stage {
        case .intro:
            copyBlock(title: PairingText.intro.title, message: PairingText.intro.message)
            Button {
                startScanning()
            } label: {
                Label("Escanear el QR", systemImage: "qrcode.viewfinder")
            }
            .filledButton(.primary)
            manualButton
        case .scanning:
            copyBlock(title: "Emparejar con el servidor", message: PairingText.scanning)
            if let scanHint {
                Label(scanHint, systemImage: "exclamationmark.triangle")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.warnText)
            }
            manualButton
            Button("Cancelar") {
                wantsCamera = false
                scanHint = nil
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.Size.hit)
            .tint(Palette.accent)
        case .connecting:
            HStack(spacing: Metrics.Space.ml) {
                ProgressView()
                Text(PairingText.connecting(serverName: serverName))
                    .textLevel(.bodyStrong)
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: Metrics.Size.hit)
            .accessibilityElement(children: .combine)
        case .paired:
            Label(PairingText.paired(deviceName: services.pairing.device?.name), systemImage: "checkmark.circle.fill")
                .textLevel(.bodyStrong)
                .foregroundStyle(Palette.okText)
        case .failed(let failure):
            copy(PairingText.failure(failure, addresses: hintAddresses))
        case .cameraDenied:
            copy(PairingText.cameraDenied)
        case .cameraUnavailable:
            copy(PairingText.cameraUnavailable)
        }
    }

    private var manualButton: some View {
        Button {
            showingManual = true
        } label: {
            Label("Escribir a mano", systemImage: "keyboard")
                .frame(maxWidth: .infinity)
        }
        .cristalButton()
        .controlSize(.large)
    }

    private func copyBlock(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            Text(title)
                .textLevel(.legTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textLevel(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func copy(_ copy: PairingCopy) -> some View {
        copyBlock(title: copy.title, message: copy.message)
        if let hint = copy.hint {
            Text(hint)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(Array(copy.actions.enumerated()), id: \.offset) { index, action in
            actionButton(action, primary: index == 0)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: PairingAction, primary: Bool) -> some View {
        let title = PairingText.actionTitle(action)
        if primary {
            Button(title) { perform(action) }
                .filledButton(.primary)
        } else {
            Button {
                perform(action)
            } label: {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .cristalButton()
            .controlSize(.large)
        }
    }

    /// Las direcciones que se han probado: las del QR leído aquí, las del
    /// enlace que llegó de fuera o las guardadas.
    private var hintAddresses: [String] {
        if !triedAddresses.isEmpty { return triedAddresses }
        if let link = services.pairing.lastLink { return link.addresses }
        return services.config.candidates
    }

    private var serverName: String? {
        if let name = services.pairing.lastLink?.serverName, !name.isEmpty { return name }
        let saved = services.pairing.serverName
        return saved.isEmpty ? nil : saved
    }

    // MARK: - Acciones

    private func perform(_ action: PairingAction) {
        switch action {
        case .scanAgain:
            services.pairing.dismissFailure()
            startScanning()
        case .typeManually:
            showingManual = true
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }

    /// Abre la cámara. El permiso se pide aquí, cuando ya se ha explicado
    /// para qué es.
    private func startScanning() {
        scanHint = nil
        services.pairing.dismissFailure()
        let current = CameraPermission.current()
        camera = current
        guard current == .notDetermined else {
            wantsCamera = true
            return
        }
        Task {
            // TODO-COMPILAR: la versión `async` de `requestAccess(for:)`. Si
            // no casa, la de `completionHandler` con una continuación.
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            camera = granted ? .authorized : CameraPermission.current()
            wantsCamera = true
        }
    }

    /// Un QR leído.
    private func scanned(_ payload: String) {
        guard stage == .scanning else { return }
        let decision = PairingScanDecision.decide(payload)
        switch decision {
        case .pair(let url):
            scanHint = nil
            triedAddresses = (try? PairingLink.parse(url))?.addresses ?? []
            let pairing = services.pairing
            Task {
                await pairing.handle(url: url)
            }
        case .otherTrajetLink, .notTrajet:
            scanHint = decision.hint
        }
    }

    /// Emparejado. La háptica va por UIKit: en la raíz esta pantalla se va
    /// enseguida (RootView deja ver el «Listo» 1,2 s y funde a las pestañas).
    private func succeeded() {
        guard !didPair else { return }
        didPair = true
        wantsCamera = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement,
                             argument: PairingText.paired(deviceName: services.pairing.device?.name))
        if isPresented {
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                dismiss()
            }
        }
    }
}

#if DEBUG
#Preview("Emparejar (demo)") {
    DemoServicesPreview("emparejar", loadsBoard: false) {
        PairingFlowView()
    }
}
#endif
