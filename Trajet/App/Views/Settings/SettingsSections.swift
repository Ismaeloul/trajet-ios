import SwiftUI

// Secciones de Ajustes: estado del servidor, cuota (R46), recolector y
// traductor; modo trayecto; permisos; widgets y Live Activity (R60). Los
// textos salen de SettingsLogic.swift.

// MARK: - Estado del servidor, cuota, recolector y traductor

/// Lo que dice `/api/v1/health` (no gasta cuota). La clave de PRIM NUNCA se
/// enseña: solo si funciona y de dónde sale.
struct SettingsHealthSections: View {
    let health: HealthStore

    var body: some View {
        Section {
            if let h = health.health {
                LabeledContent {
                    SettingsStatusValue(status: PrimKeyText.status(h.prim))
                } label: {
                    Text("Clave de PRIM")
                }
                if let source = PrimKeyText.source(h.prim) {
                    LabeledContent("De dónde sale", value: source)
                }
                if let advice = PrimKeyText.advice(h.prim) {
                    Label(advice, systemImage: "key.fill")
                        .textLevel(.footnote)
                        .foregroundStyle(PrimKeyText.status(h.prim).tone.color)
                }
                if let lastError = h.prim.lastError, !lastError.isEmpty {
                    VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                        Text("Último fallo con PRIM")
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.ink3)
                        Text(lastError)
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !h.ok {
                    Label("La base de datos del servidor no está al día. Reinícialo desde Umbrel.",
                          systemImage: "exclamationmark.triangle")
                        .textLevel(.footnote)
                        .foregroundStyle(Palette.warnText)
                }
            } else if health.isLoading {
                HStack(spacing: Metrics.Space.sm) {
                    ProgressView()
                    Text("Preguntando al servidor…")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                }
                .frame(minHeight: Metrics.Size.hit)
            }
            if let error = health.lastError {
                Label(error.errorDescription ?? "No se ha podido preguntar al servidor.",
                      systemImage: error.isNetwork ? "wifi.slash" : "exclamationmark.triangle")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.badText)
            }
            Button {
                Task { await health.load() }
            } label: {
                HStack(spacing: Metrics.Space.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Comprobar ahora")
                }
                .frame(minHeight: Metrics.Size.hit)
            }
            .disabled(health.isLoading)
        } header: {
            settingsHeader("Estado del servidor")
        } footer: {
            Text(checkedText)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }

        if let h = health.health {
            Section {
                if let overall = QuotaText.overall(h.quota) {
                    Label(overall.text, systemImage: "gauge.with.dots.needle.67percent")
                        .textLevel(.footnote)
                        .foregroundStyle(overall.tone.color)
                }
                let endpoints = QuotaText.ordered(h.quota.endpoints)
                if endpoints.isEmpty {
                    Text("Hoy aún no se ha gastado nada.")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                } else {
                    ForEach(endpoints) { endpoint in
                        SettingsQuotaRow(endpoint: endpoint)
                    }
                }
            } header: {
                settingsHeader("Cuota de PRIM hoy")
            } footer: {
                Text(QuotaText.footer(h.quota))
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }

            Section {
                statusRow("Recolector de andenes", status: CollectorText.status(h.collector),
                          detail: CollectorText.detail(h.collector), symbol: "tram.fill")
                statusRow("Traductor de avisos", status: TranslatorText.status(h.translator),
                          detail: TranslatorText.detail(h.translator), symbol: "brain")
            } header: {
                settingsHeader("Recolector y traductor")
            } footer: {
                Text("El recolector aprende en qué vía sale cada tren (la vía probable). El traductor pasa al español los avisos, que llegan en francés.")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    private var checkedText: String {
        var text = "No gasta cuota. Nunca se enseña la clave: solo si funciona y de dónde sale."
        if let checked = health.checkedAt {
            text += " Comprobado a las \(ClockTime.text(from: checked))."
        }
        return text
    }

    private func statusRow(_ title: String, status: SettingsStatus, detail: String?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.hair) {
            LabeledContent {
                SettingsStatusValue(status: status)
            } label: {
                Label(title, systemImage: symbol)
            }
            if let detail {
                Text(detail)
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .frame(minHeight: Metrics.Size.hit)
        .accessibilityElement(children: .combine)
    }
}

/// Un endpoint de la cuota: nombre («Tablero», «Avisos», «Buscador»),
/// «318 de 1000», barra con el color de su nivel y lo que queda (R46).
private struct SettingsQuotaRow: View {
    let endpoint: QuotaEndpoint

    var body: some View {
        let level = QuotaText.level(endpoint)
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(endpoint.label)
                    .textLevel(.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.Space.sm)
                Text(QuotaText.usage(endpoint))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Palette.ink2)
            }
            ProgressView(value: Double(min(max(endpoint.used, 0), max(endpoint.cap, 1))),
                         total: Double(max(endpoint.cap, 1)))
                .tint(level.tone.color)
            HStack(alignment: .firstTextBaseline) {
                Text(QuotaText.remaining(endpoint))
                    .foregroundStyle(Palette.ink3)
                Spacer(minLength: Metrics.Space.sm)
                Text(level.text)
                    .foregroundStyle(level.tone.color)
            }
            .textLevel(.footnote)
        }
        .padding(.vertical, Metrics.Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuotaText.spoken(endpoint))
    }
}

// MARK: - Modo trayecto

/// Tiempo máximo, geocercas (piden «Siempre») y estaciones vigiladas
/// (`TripSettings`, se guardan al cambiarlas).
struct SettingsTripSection: View {
    @Bindable var settings: TripSettings
    let trip: TripController
    @Binding var geofencesOn: Bool
    let askingAlways: Bool
    let alwaysDenied: Bool
    let openSettings: @MainActor () -> Void

    var body: some View {
        Section {
            Stepper(value: $settings.maxMinutes, in: TripSettings.maxMinutesRange, step: TripSettingsText.step) {
                LabeledContent("Tiempo máximo", value: TripSettingsText.maxMinutes(settings.maxMinutes))
            }
            .accessibilityValue(TripSettingsText.maxMinutes(settings.maxMinutes))
            Toggle(isOn: $geofencesOn) {
                VStack(alignment: .leading, spacing: Metrics.Space.hair) {
                    Text("Geocercas en tus estaciones")
                        .textLevel(.body)
                    if askingAlways {
                        Text("Pidiendo el permiso…")
                            .textLevel(.footnote)
                            .foregroundStyle(Palette.ink3)
                    }
                }
            }
            .tint(Palette.accent)
            .disabled(askingAlways)
            if alwaysDenied || (settings.geofencesEnabled && !trip.canUseGeofences) {
                Label(TripSettingsText.alwaysNeeded, systemImage: "location.slash")
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.warnText)
                Button {
                    openSettings()
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                        .frame(minHeight: Metrics.Size.hit)
                }
            }
        } header: {
            settingsHeader("Modo trayecto")
        } footer: {
            Text(TripSettingsText.maxMinutesFooter + " " + TripSettings.geofenceExplanation)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }

        if settings.geofencesEnabled {
            Section {
                let stations = trip.watchableStations()
                if stations.isEmpty {
                    Text("Aún no hay rutas con paradas que vigilar.")
                        .textLevel(.callout)
                        .foregroundStyle(Palette.ink2)
                } else {
                    ForEach(stations) { station in
                        stationRow(station)
                    }
                }
                if !settings.usesDefaultStations {
                    Button("Volver a las de siempre") {
                        settings.resetWatchedStations()
                    }
                    .frame(minHeight: Metrics.Size.hit)
                }
            } header: {
                settingsHeader("Estaciones vigiladas")
            } footer: {
                Text(TripSettingsText.stationsFooter(usesDefault: settings.usesDefaultStations))
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    private func stationRow(_ station: StationOption) -> some View {
        let isOn = settings.watchedStationIDs.contains(station.id)
        return Button {
            var ids = settings.watchedStationIDs
            if isOn { ids.remove(station.id) } else { ids.insert(station.id) }
            settings.watchedStationIDs = ids
        } label: {
            HStack(spacing: Metrics.Space.ml) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                Text(station.name.isEmpty ? station.id : station.name)
                    .textLevel(.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Metrics.Size.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(station.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Permisos

/// Ubicación, cámara y red local, con el botón a Ajustes del sistema.
struct SettingsPermissionsSection: View {
    let location: LocationAuthorization
    let camera: CameraPermission
    let openSettings: @MainActor () -> Void

    var body: some View {
        Section {
            permissionRow("Ubicación", status: PermissionText.location(location),
                          note: PermissionText.locationNote(location))
            permissionRow("Cámara", status: PermissionText.camera(camera), note: PermissionText.cameraNote)
            permissionRow("Red local", status: SettingsStatus(text: "la pide iOS", tone: .neutral),
                          note: PermissionText.localNetworkNote)
            Button {
                openSettings()
            } label: {
                Label("Abrir Ajustes de Trajet", systemImage: "gear")
                    .frame(minHeight: Metrics.Size.hit)
            }
        } header: {
            settingsHeader("Permisos")
        }
    }

    private func permissionRow(_ title: String, status: SettingsStatus, note: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.hair) {
            LabeledContent {
                SettingsStatusValue(status: status)
            } label: {
                Text(title)
            }
            Text(note)
                .textLevel(.footnote)
                .foregroundStyle(Palette.ink3)
        }
        .frame(minHeight: Metrics.Size.hit)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Widgets y Live Activity (R60)

struct SettingsExtrasSection: View {
    let extras: ExtrasAvailability
    let openSettings: @MainActor () -> Void

    var body: some View {
        Section {
            LabeledContent {
                SettingsStatusValue(status: extras.widgets)
            } label: {
                Text("Widgets")
            }
            LabeledContent {
                SettingsStatusValue(status: extras.liveActivity)
            } label: {
                Text("Live Activity")
            }
            if extras == .available(liveActivitiesEnabled: false) {
                Button {
                    openSettings()
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                        .frame(minHeight: Metrics.Size.hit)
                }
            }
        } header: {
            settingsHeader("Widgets y Live Activity")
        } footer: {
            if let explanation = extras.explanation {
                Text(explanation)
                    .textLevel(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
        }
    }
}
