import SwiftUI

/// Ajustes: dónde está el servidor y si se le está llegando.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var health: HealthResponse?
    @State private var checking = false
    @State private var checkError: String?

    var body: some View {
        @Bindable var config = model.config

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Red de casa") {
                        TextField(ServerConfig.defaultLAN, text: $config.lan)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    LabeledContent("Tailscale") {
                        TextField(ServerConfig.defaultTailscale, text: $config.tailscale)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("Se prueban las dos, en este orden, y se recuerda la que responde. La de casa es más rápida; Tailscale funciona desde la calle.")
                }

                Section("Estado") {
                    if let host = model.config.preferred {
                        LabeledContent("Conectado por",
                                       value: model.config.label(for: host))
                    }

                    if let health {
                        LabeledContent("Servidor",
                                       value: health.ok ? "responde" : "con problemas")
                        LabeledContent("Hora en París", value: health.nowParis)
                        LabeledContent("Traductor",
                                       value: health.translator.ok
                                       ? health.translator.model : "no disponible")
                        ForEach(health.quota.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(quotaLabel(key), value: "\(value) / 1000")
                        }
                        if let last = health.lastError, !last.isEmpty {
                            LabeledContent("Último error", value: last)
                                .foregroundStyle(Palette.warn)
                        }
                    } else if let checkError {
                        Text(checkError).foregroundStyle(Palette.bad)
                    }

                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Text("Comprobar ahora")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                }

                Section {
                    Button("Restablecer direcciones", role: .destructive) {
                        model.config.resetToDefaults()
                    }
                } footer: {
                    Text("La cuota es de 1000 llamadas al día por endpoint y se reinicia a medianoche UTC. El tablero se refresca cada 30 s y solo mientras lo estás mirando.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .font(.system(size: 15, weight: .heavy))
                }
            }
            .task { await check() }
            // Las direcciones se guardan según se escriben, para que no haya
            // que acordarse de darle a nada.
            .onChange(of: model.config.lan) { _, _ in model.config.persist() }
            .onChange(of: model.config.tailscale) { _, _ in model.config.persist() }
        }
        .preferredColorScheme(.dark)
    }

    private func quotaLabel(_ key: String) -> String {
        switch key {
        case "stop-monitoring": "Tablero"
        case "general-message": "Avisos"
        case "navitia": "Buscador"
        default: key
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            health = try await model.api.health()
            checkError = nil
        } catch {
            health = nil
            checkError = (error as? TrajetError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
