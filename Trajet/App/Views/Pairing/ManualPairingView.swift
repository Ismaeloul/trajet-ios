import SwiftUI

/// Emparejar a mano (sistema.md §7.17, A28): el código del panel y las
/// direcciones del servidor (casa y/o Tailscale). Sin direcciones, se usan
/// las que ya hubiera guardadas.
///
/// El código se acepta como lo escribe una persona («abcd efgh»,
/// «ABCD-EFGH»). Debajo de cada dirección se dice si iOS la dejará usar por
/// HTTP (ATS: casa, Tailscale por IP 100.x y nombres *.ts.net, sí; lo demás,
/// solo con HTTPS). Los fallos salen aquí mismo, diseñados.
struct ManualPairingView: View {
    let onPaired: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var input = ManualPairingInput()
    @State private var attempted: [String] = []
    @State private var prefilled = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case code
        case lan
        case tailscale
    }

    // Explícito: con estado privado, el inicializador sintetizado sería privado.
    init(onPaired: @escaping () -> Void) {
        self.onPaired = onPaired
    }

    private var isBusy: Bool { services.pairing.isBusy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-EFGH", text: $input.code)
                        .font(.title3.weight(.semibold).monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.next)
                        .focused($focus, equals: .code)
                        .onSubmit { focus = .lan }
                        .accessibilityLabel("Código de emparejamiento")
                        .accessibilityIdentifier("emparejar.codigo")
                } header: {
                    header("Código")
                } footer: {
                    if let problem = input.codeProblem {
                        note(problem, tone: .warn)
                    } else {
                        note("Lo da el panel del servidor al tocar «Emparejar un iPhone». Dura 5 minutos y sirve una vez.",
                             tone: .neutral)
                    }
                }

                Section {
                    addressField("http://192.168.1.10:7796", text: $input.lan, field: .lan, label: "Red de casa")
                        .onSubmit { focus = .tailscale }
                    addressField("http://100.64.0.10:7796", text: $input.tailscale, field: .tailscale, label: "Tailscale")
                        .onSubmit { submit() }
                } header: {
                    header("Dónde está el servidor")
                } footer: {
                    VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                        addressNote(input.lan, label: "Red de casa")
                        addressNote(input.tailscale, label: "Tailscale")
                        note("Con una basta. Si pones las dos, se prueba primero la de casa.", tone: .neutral)
                    }
                }

                if let failure = services.pairing.failure {
                    let copy = PairingText.failure(failure, addresses: attempted.isEmpty ? services.config.candidates : attempted)
                    Section {
                        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                            Label(copy.title, systemImage: "exclamationmark.triangle.fill")
                                .textLevel(.bodyStrong)
                                .foregroundStyle(Palette.badText)
                            Text(copy.message)
                                .textLevel(.callout)
                                .foregroundStyle(Palette.ink)
                            if let hint = copy.hint {
                                Text(hint)
                                    .textLevel(.footnote)
                                    .foregroundStyle(Palette.ink2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: Metrics.Space.sm) {
                            if isBusy {
                                ProgressView()
                                    .tint(Palette.onAccent)
                                Text(services.pairing.phase == .checking ? "Buscando el servidor…" : "Emparejando…")
                            } else {
                                Image(systemName: "link")
                                Text("Emparejar")
                            }
                        }
                    }
                    .filledButton(.primary)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("emparejar.enviar")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Escribir a mano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            prefill()
            services.pairing.dismissFailure()
            focus = .code
        }
    }

    private var canSubmit: Bool {
        !isBusy && input.canSubmit(hasSavedAddresses: services.config.hasAddresses)
    }

    // MARK: - Piezas

    private func header(_ text: String) -> some View {
        Text(text)
            .textLevel(.kicker)
            .foregroundStyle(Palette.ink3)
    }

    private func addressField(_ prompt: String, text: Binding<String>, field: Field, label: String) -> some View {
        LabeledContent {
            TextField(prompt, text: text)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(field == .tailscale ? .go : .next)
                .focused($focus, equals: field)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        } label: {
            Text(label)
                .textLevel(.body)
                .foregroundStyle(Palette.ink)
        }
    }

    @ViewBuilder
    private func addressNote(_ raw: String, label: String) -> some View {
        let kind = ServerAddressRules.classify(raw)
        if let text = ServerAddressRules.note(kind) {
            note("\(label): \(text)", tone: ServerAddressRules.tone(kind))
        }
    }

    private func note(_ text: String, tone: SettingsTone) -> some View {
        Text(text)
            .textLevel(.footnote)
            .foregroundStyle(tone == .warn ? Palette.warnText : Palette.ink3)
    }

    // MARK: - Acciones

    /// Las direcciones que ya tenga el iPhone (emparejar de nuevo, o la demo).
    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        if input.lan.isEmpty { input.lan = services.config.lanURL }
        if input.tailscale.isEmpty { input.tailscale = services.config.tailscaleURL }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let current = input
        attempted = current.typedAddresses
        let pairing = services.pairing
        Task {
            let ok = await pairing.pair(code: current.code, lanURL: current.lanURL, tailscaleURL: current.tailscaleURL)
            if ok { onPaired() }
        }
    }
}

#if DEBUG
#Preview("Emparejar a mano (demo)") {
    DemoServicesPreview("emparejar", loadsBoard: false) {
        ManualPairingView {}
    }
}
#endif
