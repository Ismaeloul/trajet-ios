import SwiftUI
import UIKit

/// Ajustes (F50–F52, sistema.md §7.15). Se abre como hoja desde la cabecera
/// del tablero o con `trajet://ajustes`: trae su propio `NavigationStack` y
/// su «Cerrar».
///
/// - Servidor: nombre y direcciones de casa y Tailscale, que se guardan según
///   se escriben (R61); «Probar conexión» (un `ping` a cada una: cuál
///   responde); «Restablecer direcciones» (vuelve a las del emparejamiento y
///   olvida la preferida). Aviso de ATS: Tailscale por IP 100.x usa la
///   excepción que ya lleva la app, y *.ts.net también vale.
/// - Este iPhone: cómo lo ve el servidor, «Emparejar de nuevo» y
///   «Desemparejar» (con confirmación).
/// - Estado del servidor (`HealthStore`, no gasta cuota): la clave de PRIM
///   en uso SIN enseñarla (estado y origen), la cuota por endpoint con su
///   nivel y el reinicio a medianoche UTC (R46), el recolector de andenes y
///   el traductor.
/// - Tablero («Vibrar cuando aparece la vía»), modo trayecto (tiempo
///   máximo, geocercas, estaciones vigiladas), permisos (con el botón a
///   Ajustes del sistema), widgets y Live Activity (si no están, por qué:
///   R60) y la versión.
struct SettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage(BoardPreferences.platformHapticKey) private var platformHaptic = true

    @State private var probe = ConnectionProbeModel()
    @State private var camera: CameraPermission = .notDetermined
    @State private var extras: ExtrasAvailability = .lite
    @State private var geofencesOn = false
    @State private var askingAlways = false
    @State private var alwaysDenied = false
    @State private var confirmingUnpair = false
    @State private var unpairing = false
    @State private var repairing = false

    var body: some View {
        NavigationStack {
            List {
                SettingsServerSection(config: services.config, probe: probe, isDemo: services.isDemo,
                                      onProbe: { probeConnection() })
                deviceSection
                SettingsHealthSections(health: services.health)
                boardSection
                SettingsTripSection(settings: services.tripSettings, trip: services.trip,
                                    geofencesOn: $geofencesOn, askingAlways: askingAlways,
                                    alwaysDenied: alwaysDenied, openSettings: { openSystemSettings() })
                SettingsPermissionsSection(location: services.trip.location.authorization, camera: camera,
                                           openSettings: { openSystemSettings() })
                SettingsExtrasSection(extras: extras, openSettings: { openSystemSettings() })
                aboutSection
                unpairSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .refreshable {
                await services.health.load()
            }
        }
        .task {
            await services.health.load()
        }
        .onAppear {
            refreshSystemState()
            geofencesOn = services.tripSettings.geofencesEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver de Ajustes del sistema con algún permiso cambiado.
            if phase == .active { refreshSystemState() }
        }
        .onChange(of: geofencesOn) { _, on in
            geofencesToggled(on)
        }
        .onChange(of: services.tripSettings.geofencesEnabled) { _, on in
            if geofencesOn != on { geofencesOn = on }
        }
        .confirmationDialog("¿Desemparejar este iPhone?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
            Button("Desemparejar", role: .destructive) { unpair() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El servidor retirará la llave de este iPhone y tendrás que escanear otro QR del panel para volver a usar la app.")
        }
        .fullScreenCover(isPresented: $repairing) {
            PairingFlowView()
                .environment(services)
        }
    }

    // MARK: - Este iPhone

    private var deviceSection: some View {
        let device = services.health.device ?? services.pairing.device
        return Section {
            if let device {
                LabeledContent("Nombre", value: device.name.isEmpty ? "iPhone" : device.name)
                let details = [DeviceText.detail(device), DeviceText.pairedOn(device), DeviceText.lastUsed(device)]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            } else {
                Text("Emparejado. El servidor dirá cómo lo ve al comprobar el estado.")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
            Button {
                repairing = true
            } label: {
                Label("Emparejar de nuevo", systemImage: "qrcode.viewfinder")
                    .frame(minHeight: Metrics.Size.hit)
            }
            .disabled(unpairing)
        } header: {
            settingsHeader("Este iPhone")
        } footer: {
            Text("Si emparejas de nuevo, el emparejamiento antiguo sigue en la lista del panel: quítalo desde allí.")
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }

    // MARK: - Tablero

    private var boardSection: some View {
        Section {
            Toggle(isOn: $platformHaptic) {
                Text("Vibrar cuando aparece la vía")
                    .textLevel(.body)
            }
            .tint(Palette.accent)
        } header: {
            settingsHeader("Tablero")
        } footer: {
            Text("Solo con el dato en directo y una vez por tren, en la primera salida de cada tramo.")
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }

    // MARK: - Acerca de

    private var aboutSection: some View {
        Section {
            LabeledContent("Versión de la app", value: AppVersionText.current)
            if let health = services.health.health {
                if !health.version.isEmpty {
                    LabeledContent("Versión del servidor", value: health.version)
                }
                if !health.nowParis.isEmpty {
                    LabeledContent("Hora en París", value: String(health.nowParis.suffix(8)))
                }
            }
            if services.isDemo {
                Text("Modo demostración: el servidor es de mentira y vive dentro de la app.")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        } header: {
            settingsHeader("Acerca de")
        }
    }

    // MARK: - Desemparejar

    private var unpairSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingUnpair = true
            } label: {
                HStack(spacing: Metrics.Space.sm) {
                    if unpairing {
                        ProgressView()
                    }
                    Text("Desemparejar este iPhone")
                        .foregroundStyle(Palette.badText)
                }
                .frame(maxWidth: .infinity, minHeight: Metrics.Size.hit)
            }
            .disabled(unpairing)
        }
    }

    // MARK: - Acciones

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func refreshSystemState() {
        camera = CameraPermission.current()
        extras = ExtrasAvailability.current()
    }

    /// «Probar conexión»: ping a las dos direcciones a la vez. Si la
    /// preferida no responde y otra sí, se recuerda la que responde (R42).
    private func probeConnection() {
        let api = services.api
        let config = services.config
        let probe = self.probe
        Task {
            let answering = await probe.run(lanURL: config.lanURL, tailscaleURL: config.tailscaleURL) { url in
                try await api.ping(baseURL: url)
            }
            guard let answering else { return }
            let preferred = config.preferredURL
            let preferredAnswers = (preferred != nil && preferred == ServerConfig.normalize(config.lanURL) && probe.lan.answers)
                || (preferred != nil && preferred == ServerConfig.normalize(config.tailscaleURL) && probe.tailscale.answers)
            if !preferredAnswers {
                config.remember(answering)
            }
        }
    }

    /// El interruptor de las geocercas. Encenderlo pide «Siempre» si hace
    /// falta (con la explicación ya a la vista); si iOS no lo da, se queda
    /// apagado y se dice cómo darlo.
    private func geofencesToggled(_ on: Bool) {
        let settings = services.tripSettings
        let trip = services.trip
        guard on else {
            if settings.geofencesEnabled { settings.geofencesEnabled = false }
            alwaysDenied = false
            return
        }
        guard !settings.geofencesEnabled, !askingAlways else { return }
        if trip.canUseGeofences {
            settings.geofencesEnabled = true
            alwaysDenied = false
            return
        }
        askingAlways = true
        Task {
            await trip.requestAlwaysForGeofences()
            askingAlways = false
            alwaysDenied = !settings.geofencesEnabled
            if !settings.geofencesEnabled { geofencesOn = false }
        }
    }

    /// Desemparejar: se para el trayecto si lo hay (su Live Activity no
    /// tendría ya servidor), se pide al servidor que retire la llave y se
    /// olvida todo aquí. La raíz pasa a la pantalla de emparejar.
    private func unpair() {
        guard !unpairing else { return }
        unpairing = true
        let trip = services.trip
        let pairing = services.pairing
        Task {
            if trip.isActive {
                await trip.stop(reason: .manual)
            }
            await pairing.unpair()
            unpairing = false
        }
    }
}

extension SettingsTone {
    /// Los colores de texto de estado (los rellenos no pasan AA como texto).
    var color: Color {
        switch self {
        case .ok: Palette.okText
        case .warn: Palette.warnText
        case .bad: Palette.badText
        case .neutral: Palette.ink2
        }
    }
}

/// Rótulo de sección de Ajustes.
@MainActor
func settingsHeader(_ text: String) -> some View {
    Text(text)
        .textLevel(.kicker)
        .foregroundStyle(Palette.ink3)
}

/// Un valor de estado a la derecha, con su color.
struct SettingsStatusValue: View {
    let status: SettingsStatus

    var body: some View {
        Text(status.text)
            .textLevel(.body)
            .foregroundStyle(status.tone.color)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Servidor

/// Nombre y direcciones del servidor (R61: se guardan según se escriben).
private struct SettingsServerSection: View {
    @Bindable var config: ServerConfig
    let probe: ConnectionProbeModel
    let isDemo: Bool
    let onProbe: @MainActor () -> Void

    var body: some View {
        Section {
            LabeledContent {
                TextField("Trajet de casa", text: $config.serverName)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Nombre del servidor")
            } label: {
                Text("Nombre")
            }
            addressRow("Red de casa", text: $config.lanURL, prompt: "http://192.168.1.10:7796", result: probe.lan)
            addressRow("Tailscale", text: $config.tailscaleURL, prompt: "http://100.64.0.10:7796", result: probe.tailscale)
            if let via = config.connectedVia {
                LabeledContent("Conectado por", value: via)
            }
            Button {
                onProbe()
            } label: {
                HStack(spacing: Metrics.Space.sm) {
                    if probe.isRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(probe.isRunning ? "Probando…" : "Probar conexión")
                }
                .frame(minHeight: Metrics.Size.hit)
            }
            .disabled(probe.isRunning || !config.hasAddresses)
            Button(role: .destructive) {
                config.reset()
                probe.reset()
            } label: {
                Text("Restablecer direcciones")
                    .foregroundStyle(Palette.badText)
                    .frame(minHeight: Metrics.Size.hit)
            }
            .accessibilityHint("Vuelve a las direcciones del emparejamiento y olvida la preferida")
        } header: {
            settingsHeader("Servidor")
        } footer: {
            Text(ServerAddressRules.footer)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
    }

    private func addressRow(_ label: String, text: Binding<String>, prompt: String,
                            result: ConnectionProbeResult) -> some View {
        let kind = ServerAddressRules.classify(text.wrappedValue)
        let note = isDemo ? nil : ServerAddressRules.note(kind)
        return VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            LabeledContent {
                TextField(prompt, text: text)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(label)
            } label: {
                Text(label)
            }
            .frame(minHeight: Metrics.Size.hit)
            if let status = result.status {
                Text(status.text)
                    .textLevel(.footnote)
                    .foregroundStyle(status.tone.color)
            }
            if let note {
                Text(note)
                    .textLevel(.footnote)
                    .foregroundStyle(ServerAddressRules.tone(kind) == .warn ? Palette.warnText : Palette.ink3)
            }
        }
    }
}

#if DEBUG
#Preview("Ajustes (demo)") {
    DemoServicesPreview("cincoTramos", loadsBoard: false) {
        SettingsScreen()
    }
}

#Preview("Ajustes: servidor sin clave") {
    DemoServicesPreview("sinClave", loadsBoard: false) {
        SettingsScreen()
    }
}
#endif
