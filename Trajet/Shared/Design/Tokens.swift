import SwiftUI
import UIKit

// Colores del sistema de diseño «Cristal» (dirección B del laboratorio).
//
// La fuente de verdad NO es este fichero: es `design-lab/tools/tokens.mjs`,
// que parte de los valores OKLCH de B, los convierte a sRGB, comprueba el
// contraste WCAG de cada pareja texto/fondo en claro, oscuro y con «Aumentar
// contraste», y reescribe los dos bloques marcados como generados. Para
// cambiar un color: se cambia en el script y se ejecuta
// `node design-lab/tools/tokens.mjs`. Explicación completa en
// `docs/diseno/sistema.md`.
//
// Reglas que viven aquí:
// - Los colores de línea (`line_color`) son los ÚNICOS saturados junto a los
//   estados (R12). Nada de aquí compite con ellos: neutros casi grises, un
//   azul solo para lo que se toca, el amarillo solo para la vía confirmada.
// - Los minutos y la vía van en superficies OPACAS (`ticket`, `via`): se
//   leen a contraluz (R1). El cristal es para los controles.

/// Un color sRGB con alfa, en coma flotante (0…1).
struct RGBA: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Este color (con su alfa) pintado encima de `base`, ya opaco. Es lo que
    /// usa «Reducir transparencia» y lo que miden los tests de contraste.
    func composited(over base: RGBA) -> RGBA {
        let a = alpha
        return RGBA(red * a + base.red * (1 - a),
                    green * a + base.green * (1 - a),
                    blue * a + base.blue * (1 - a),
                    1)
    }

    /// Luminancia relativa de WCAG 2.x (sin mirar el alfa).
    var relativeLuminance: Double {
        func channel(_ v: Double) -> Double {
            let c = min(1, max(0, v))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Relación de contraste WCAG (1…21). Si este color lleva alfa, se mide
    /// ya compuesto sobre `other`.
    func contrast(with other: RGBA) -> Double {
        let fg = alpha < 1 ? composited(over: other) : self
        let a = fg.relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Un token de color con sus cuatro variantes: claro, oscuro, y las dos con
/// «Aumentar contraste» (Ajustes › Accesibilidad › Pantalla y tamaño de texto).
struct DynamicColor: Sendable, Hashable {
    let light: RGBA
    let dark: RGBA
    let lightHC: RGBA
    let darkHC: RGBA

    func resolve(dark isDark: Bool, highContrast: Bool) -> RGBA {
        switch (isDark, highContrast) {
        case (false, false): light
        case (true, false): dark
        case (false, true): lightHC
        case (true, true): darkHC
        }
    }

    func resolve(in traits: UITraitCollection) -> RGBA {
        resolve(dark: traits.userInterfaceStyle == .dark,
                highContrast: traits.accessibilityContrast == .high)
    }

    /// Color que cambia solo con el modo claro/oscuro y con «Aumentar
    /// contraste», también dentro de widgets y hojas.
    ///
    /// TODO-COMPILAR: se da por hecho que el cierre de
    /// `UIColor(dynamicProvider:)` y `UITraitCollection` no están aislados en
    /// el `MainActor` (UIKit los declara seguros entre hilos). Si Swift 6 se
    /// queja, la alternativa segura es mover estos colores a un catálogo de
    /// assets con variantes «Any / Dark / High Contrast» (el script ya sabe
    /// escribir colorsets: ver `colorset()` en tokens.mjs).
    var uiColor: UIColor {
        let spec = self
        return UIColor { traits in spec.resolve(in: traits).uiColor }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Para cuando la vista ya sabe su esquema (capturas, vistas previas,
    /// widgets con un esquema fijo, tests de contraste).
    func color(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        resolve(dark: scheme == .dark, highContrast: contrast == .increased).color
    }
}

/// Los tokens crudos (las cuatro variantes de cada color). Los usan los tests
/// de contraste y quien necesite el valor exacto; las vistas usan `Palette`.
enum Tokens {
    // <generado:tokens>
    // Generado por design-lab/tools/tokens.mjs a partir de OKLCH. No editar a mano:
    // se cambia el script y se vuelve a ejecutar. Orden: claro, oscuro,
    // claro con «Aumentar contraste», oscuro con «Aumentar contraste».

    // MARK: fondo
    /// Fondo de pantalla (debajo del mapa y de las listas).
    /// `--bg` · claro oklch(96% 0.003 260) = #F0F2F4 · oscuro oklch(12% 0.005 260) = #050607
    static let bg = DynamicColor(
        light: RGBA(0.9431, 0.9480, 0.9559),
        dark: RGBA(0.0193, 0.0226, 0.0286),
        lightHC: RGBA(0.9431, 0.9480, 0.9559),
        darkHC: RGBA(0.0193, 0.0226, 0.0286))
    /// Tarjeta OPACA (tramo, ruta, opción).
    /// `--card (opaca)` · claro oklch(99.2% 0.001 260) = #FCFCFD · oscuro oklch(18.5% 0.005 260) = #111315
    static let surface = DynamicColor(
        light: RGBA(0.9880, 0.9896, 0.9923),
        dark: RGBA(0.0681, 0.0735, 0.0821),
        lightHC: RGBA(0.9880, 0.9896, 0.9923),
        darkHC: RGBA(0.0681, 0.0735, 0.0821))
    /// Ficha dentro de una tarjeta (salidas 2.ª–4.ª), campos, segmentos.
    /// `--rule sobre --card` · claro oklch(93.5% 0.004 260) = #E8E9EC · oscuro oklch(27% 0.005 260) = #252629
    static let surfaceHi = DynamicColor(
        light: RGBA(0.9092, 0.9156, 0.9261),
        dark: RGBA(0.1450, 0.1509, 0.1604),
        lightHC: RGBA(0.9092, 0.9156, 0.9261),
        darkHC: RGBA(0.1450, 0.1509, 0.1604))
    /// Filetes y separadores (con alfa).
    /// `--rule` · claro oklch(0% 0 0 / 0.08) = #00000014 · oscuro oklch(100% 0 0 / 0.1) = #FFFFFF1A
    static let rule = DynamicColor(
        light: RGBA(0.0000, 0.0000, 0.0000, 0.080),
        dark: RGBA(1.0000, 1.0000, 1.0000, 0.100),
        lightHC: RGBA(0.0000, 0.0000, 0.0000, 0.220),
        darkHC: RGBA(1.0000, 1.0000, 1.0000, 0.280))

    // MARK: tinta
    /// Texto principal.
    /// `--ink` · claro oklch(15% 0.01 260) = #090B0F · oscuro oklch(97% 0 0) = #F5F5F5
    static let ink = DynamicColor(
        light: RGBA(0.0343, 0.0442, 0.0605),
        dark: RGBA(0.9606, 0.9606, 0.9606),
        lightHC: RGBA(0.0016, 0.0016, 0.0016),
        darkHC: RGBA(1.0000, 1.0000, 1.0000))
    /// Texto secundario (dirección, destino de fichas, metadatos).
    /// `--ink-2` · claro oklch(40% 0.01 260) = #45484D · oscuro oklch(78% 0.01 260) = #B4B8BE
    static let ink2 = DynamicColor(
        light: RGBA(0.2688, 0.2818, 0.3028),
        dark: RGBA(0.7044, 0.7198, 0.7447),
        lightHC: RGBA(0.1396, 0.1513, 0.1703),
        darkHC: RGBA(0.8370, 0.8450, 0.8578))
    /// Texto terciario (rótulos de sección, pie, «min» de las fichas).
    /// `--ink-3` · claro oklch(48% 0.01 260) = #5A5E63 · oscuro oklch(71% 0.01 260) = #9EA2A8
    static let ink3 = DynamicColor(
        light: RGBA(0.3541, 0.3678, 0.3898),
        dark: RGBA(0.6190, 0.6340, 0.6583),
        lightHC: RGBA(0.1877, 0.2000, 0.2198),
        darkHC: RGBA(0.7863, 0.7942, 0.8069))

    // MARK: cristal
    /// Relleno del cristal en iOS 17–25 (encima del material).
    /// `--glass` · claro oklch(100% 0 0 / 0.58) = #FFFFFF94 · oscuro oklch(20% 0.005 260 / 0.55) = #1516188C
    static let glass = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000, 0.580),
        dark: RGBA(0.0811, 0.0866, 0.0954, 0.550),
        lightHC: RGBA(1.0000, 1.0000, 1.0000, 0.850),
        darkHC: RGBA(0.0811, 0.0866, 0.0954, 0.850))
    /// Brillo del canto superior del cristal (iOS 17–25).
    /// `--glass-hi` · claro oklch(100% 0 0 / 0.8) = #FFFFFFCC · oscuro oklch(100% 0 0 / 0.12) = #FFFFFF1F
    static let glassHighlight = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000, 0.800),
        dark: RGBA(1.0000, 1.0000, 1.0000, 0.120),
        lightHC: RGBA(1.0000, 1.0000, 1.0000, 0.800),
        darkHC: RGBA(1.0000, 1.0000, 1.0000, 0.120))
    /// Canto del cristal (1 pt).
    /// `--glass-edge` · claro oklch(100% 0 0 / 0.6) = #FFFFFF99 · oscuro oklch(100% 0 0 / 0.14) = #FFFFFF24
    static let glassEdge = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000, 0.600),
        dark: RGBA(1.0000, 1.0000, 1.0000, 0.140),
        lightHC: RGBA(0.0000, 0.0000, 0.0000, 0.450),
        darkHC: RGBA(1.0000, 1.0000, 1.0000, 0.450))
    /// Cristal con «Reducir transparencia»: compuesto opaco de --glass sobre el fondo.
    /// `(nuevo)` · claro oklch(98.3% 0.001 260) = #F9F9FA · oscuro oklch(16.8% 0.005 260) = #0E0F11
    static let glassOpaque = DynamicColor(
        light: RGBA(0.9762, 0.9778, 0.9804),
        dark: RGBA(0.0537, 0.0589, 0.0674),
        lightHC: RGBA(0.9762, 0.9778, 0.9804),
        darkHC: RGBA(0.0537, 0.0589, 0.0674))

    // MARK: billete
    /// Fondo del billete: invierte el tema para que los minutos salten a contraluz.
    /// `--solid` · claro oklch(15% 0.01 260) = #090B0F · oscuro oklch(98% 0 0) = #F8F8F8
    static let ticket = DynamicColor(
        light: RGBA(0.0343, 0.0442, 0.0605),
        dark: RGBA(0.9737, 0.9737, 0.9737),
        lightHC: RGBA(0.0016, 0.0016, 0.0016),
        darkHC: RGBA(1.0000, 1.0000, 1.0000))
    /// Minutos y destino en el billete (AAA).
    /// `--solid-ink` · claro oklch(100% 0 0) = #FFFFFF · oscuro oklch(12% 0 0) = #060606
    static let ticketInk = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000),
        dark: RGBA(0.0223, 0.0223, 0.0223),
        lightHC: RGBA(1.0000, 1.0000, 1.0000),
        darkHC: RGBA(0.0000, 0.0000, 0.0000))
    /// Unidad «min», hora y longitud en el billete.
    /// `--solid-ink × .7/.75` · claro oklch(80% 0.005 260) = #BCBEC1 · oscuro oklch(38% 0.005 260) = #414245
    static let ticketInk2 = DynamicColor(
        light: RGBA(0.7362, 0.7440, 0.7565),
        dark: RGBA(0.2539, 0.2604, 0.2708),
        lightHC: RGBA(0.8698, 0.8698, 0.8698),
        darkHC: RGBA(0.1315, 0.1315, 0.1315))
    /// Retraso dentro del billete.
    /// `(nuevo)` · claro oklch(82% 0.14 72) = #FCB452 · oscuro oklch(50% 0.13 55) = #994A00 (mapeado a sRGB)
    static let ticketWarn = DynamicColor(
        light: RGBA(0.9869, 0.7060, 0.3211),
        dark: RGBA(0.6012, 0.2913, 0.0000),
        lightHC: RGBA(1.0000, 0.8064, 0.4704),
        darkHC: RGBA(0.4804, 0.2149, 0.0061))
    /// Fondo de la etiqueta de ritmo «Anda» / «Con calma» (con alfa, sobre el billete).
    /// `oklch(50% 0 0 / .25)` · claro oklch(50% 0 0 / 0.35) = #63636359 · oscuro oklch(50% 0 0 / 0.25) = #63636340
    static let pace = DynamicColor(
        light: RGBA(0.3886, 0.3886, 0.3886, 0.350),
        dark: RGBA(0.3886, 0.3886, 0.3886, 0.250),
        lightHC: RGBA(0.3886, 0.3886, 0.3886, 0.350),
        darkHC: RGBA(0.3886, 0.3886, 0.3886, 0.250))

    // MARK: vía
    /// Caja sólida de la vía CONFIRMADA.
    /// `--via` · claro oklch(88% 0.17 92) = #FFD32E · oscuro oklch(88% 0.17 92) = #FFD32E (mapeado a sRGB)
    static let via = DynamicColor(
        light: RGBA(1.0000, 0.8261, 0.1805),
        dark: RGBA(1.0000, 0.8261, 0.1805),
        lightHC: RGBA(1.0000, 0.8261, 0.1805),
        darkHC: RGBA(1.0000, 0.8261, 0.1805))
    /// Texto dentro de la caja de vía (AAA).
    /// `--via-ink` · claro oklch(18% 0.02 80) = #161107 · oscuro oklch(18% 0.02 80) = #161107
    static let viaInk = DynamicColor(
        light: RGBA(0.0872, 0.0652, 0.0290),
        dark: RGBA(0.0872, 0.0652, 0.0290),
        lightHC: RGBA(0.0872, 0.0652, 0.0290),
        darkHC: RGBA(0.0872, 0.0652, 0.0290))
    /// Canto de 1 pt de la caja de vía, siempre.
    /// `(nuevo)` · claro oklch(58% 0.12 85) = #9B7300 · oscuro oklch(58% 0.12 85) = #9B7300 (mapeado a sRGB)
    static let viaEdge = DynamicColor(
        light: RGBA(0.6065, 0.4523, 0.0000),
        dark: RGBA(0.6065, 0.4523, 0.0000),
        lightHC: RGBA(0.3898, 0.2828, 0.0000),
        darkHC: RGBA(0.3898, 0.2828, 0.0000))

    // MARK: interacción
    /// Azul para texto e iconos interactivos (enlaces, pestaña activa, «Guardar»).
    /// `--accent` · claro oklch(52% 0.2 258) = #0061D8 · oscuro oklch(68% 0.16 252) = #439BF7 (mapeado a sRGB)
    static let accent = DynamicColor(
        light: RGBA(0.0000, 0.3805, 0.8488),
        dark: RGBA(0.2611, 0.6089, 0.9687),
        lightHC: RGBA(0.0238, 0.2613, 0.7110),
        darkHC: RGBA(0.4766, 0.7403, 1.0000))
    /// Relleno del botón principal con texto blanco (B daba 3,7:1).
    /// `--accent (relleno)` · claro oklch(53% 0.21 258) = #0063E1 · oscuro oklch(53% 0.21 258) = #0063E1 (mapeado a sRGB)
    static let accentFill = DynamicColor(
        light: RGBA(0.0000, 0.3875, 0.8837),
        dark: RGBA(0.0000, 0.3875, 0.8837),
        lightHC: RGBA(0.0095, 0.2659, 0.7449),
        darkHC: RGBA(0.0397, 0.2917, 0.7716))
    /// Texto sobre accentFill y sobre bad.
    /// `#fff` · claro oklch(100% 0 0) = #FFFFFF · oscuro oklch(100% 0 0) = #FFFFFF
    static let onAccent = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000),
        dark: RGBA(1.0000, 1.0000, 1.0000),
        lightHC: RGBA(1.0000, 1.0000, 1.0000),
        darkHC: RGBA(1.0000, 1.0000, 1.0000))

    // MARK: estado
    /// Perturbada: icono y fondo del aviso (con alfa).
    /// `--warn` · claro oklch(76% 0.16 65) = #F59926 · oscuro oklch(76% 0.16 65) = #F59926
    static let warn = DynamicColor(
        light: RGBA(0.9613, 0.5982, 0.1483),
        dark: RGBA(0.9613, 0.5982, 0.1483),
        lightHC: RGBA(0.9613, 0.5982, 0.1483),
        darkHC: RGBA(0.9613, 0.5982, 0.1483))
    /// Texto de aviso: «Perturbada», «+2 min», «cualquier sentido».
    /// `(nuevo)` · claro oklch(50% 0.13 55) = #994A00 · oscuro oklch(80% 0.15 72) = #F8AC3D (mapeado a sRGB)
    static let warnText = DynamicColor(
        light: RGBA(0.6012, 0.2913, 0.0000),
        dark: RGBA(0.9745, 0.6745, 0.2389),
        lightHC: RGBA(0.4682, 0.2038, 0.0000),
        darkHC: RGBA(1.0000, 0.7936, 0.4577))
    /// Fondo del aviso de línea perturbada (sobre la tarjeta).
    /// `oklch(76% .16 65 / .16)` · claro oklch(76% 0.16 65 / 0.18) = #F599262E · oscuro oklch(76% 0.16 65 / 0.16) = #F5992629
    static let noticeWarn = DynamicColor(
        light: RGBA(0.9613, 0.5982, 0.1483, 0.180),
        dark: RGBA(0.9613, 0.5982, 0.1483, 0.160),
        lightHC: RGBA(0.9613, 0.5982, 0.1483, 0.180),
        darkHC: RGBA(0.9613, 0.5982, 0.1483, 0.160))
    /// Interrumpida / peligro: relleno de «Corre», del botón rojo y del banner de línea cortada (texto blanco encima).
    /// `--bad` · claro oklch(55% 0.2 25) = #CC272E · oscuro oklch(55% 0.2 25) = #CC272E
    static let bad = DynamicColor(
        light: RGBA(0.8018, 0.1512, 0.1813),
        dark: RGBA(0.8018, 0.1512, 0.1813),
        lightHC: RGBA(0.6618, 0.0761, 0.1225),
        darkHC: RGBA(0.6618, 0.0761, 0.1225))
    /// Texto de error: «Interrumpida», «pasa por la línea cortada», «Eliminar ruta».
    /// `(nuevo)` · claro oklch(50% 0.19 25) = #B71824 · oscuro oklch(72% 0.16 22) = #F97676
    static let badText = DynamicColor(
        light: RGBA(0.7173, 0.0942, 0.1397),
        dark: RGBA(0.9749, 0.4644, 0.4634),
        lightHC: RGBA(0.5533, 0.0390, 0.0890),
        darkHC: RGBA(1.0000, 0.6547, 0.6530))
    /// Fondo del aviso de línea interrumpida.
    /// `oklch(60% .21 25 / .18)` · claro oklch(60% 0.21 25 / 0.14) = #E2343924 · oscuro oklch(60% 0.21 25 / 0.2) = #E2343933
    static let noticeBad = DynamicColor(
        light: RGBA(0.8878, 0.2030, 0.2233, 0.140),
        dark: RGBA(0.8878, 0.2030, 0.2233, 0.200),
        lightHC: RGBA(0.8878, 0.2030, 0.2233, 0.140),
        darkHC: RGBA(0.8878, 0.2030, 0.2233, 0.200))
    /// Relleno verde: billete «En andén», interruptores, punto «en directo» en oscuro.
    /// `--ok` · claro oklch(72% 0.17 155) = #22C373 · oscuro oklch(72% 0.17 155) = #22C373
    static let ok = DynamicColor(
        light: RGBA(0.1327, 0.7631, 0.4528),
        dark: RGBA(0.1327, 0.7631, 0.4528),
        lightHC: RGBA(0.1327, 0.7631, 0.4528),
        darkHC: RGBA(0.1327, 0.7631, 0.4528))
    /// Texto e iconos verdes (punto «en directo» y «listo» en claro; B daba 2,1:1).
    /// `(nuevo)` · claro oklch(50% 0.13 155) = #007840 · oscuro oklch(76% 0.16 155) = #46CE83 (mapeado a sRGB)
    static let okText = DynamicColor(
        light: RGBA(0.0000, 0.4700, 0.2526),
        dark: RGBA(0.2762, 0.8084, 0.5132),
        lightHC: RGBA(0.0000, 0.3402, 0.1823),
        darkHC: RGBA(0.5126, 0.9057, 0.6596))
    /// Texto sobre el billete verde «En andén» (AAA).
    /// `#0a1a10` · claro oklch(19% 0.03 155) = #08180E · oscuro oklch(19% 0.03 155) = #08180E
    static let atStopInk = DynamicColor(
        light: RGBA(0.0308, 0.0931, 0.0540),
        dark: RGBA(0.0308, 0.0931, 0.0540),
        lightHC: RGBA(0.0308, 0.0931, 0.0540),
        darkHC: RGBA(0.0308, 0.0931, 0.0540))

    // MARK: sombra
    /// Color base de las sombras (la opacidad va en cada sombra).
    /// `oklch(0% 0 0 / …)` · claro oklch(0% 0 0) = #000000 · oscuro oklch(0% 0 0) = #000000
    static let shadow = DynamicColor(
        light: RGBA(0.0000, 0.0000, 0.0000),
        dark: RGBA(0.0000, 0.0000, 0.0000),
        lightHC: RGBA(0.0000, 0.0000, 0.0000),
        darkHC: RGBA(0.0000, 0.0000, 0.0000))

    // MARK: mapa
    /// Contorno del trazado de la línea en el mapa.
    /// `casing (map.js)` · claro oklch(100% 0 0) = #FFFFFF · oscuro oklch(0% 0 0) = #000000
    static let mapCasing = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000),
        dark: RGBA(0.0000, 0.0000, 0.0000),
        lightHC: RGBA(1.0000, 1.0000, 1.0000),
        darkHC: RGBA(0.0000, 0.0000, 0.0000))
    /// Relleno de las paradas servidas.
    /// `stopFill (app.js)` · claro oklch(100% 0 0) = #FFFFFF · oscuro oklch(19.1% 0.006 271.1) = #131417
    static let mapStopFill = DynamicColor(
        light: RGBA(1.0000, 1.0000, 1.0000),
        dark: RGBA(0.0745, 0.0784, 0.0902),
        lightHC: RGBA(1.0000, 1.0000, 1.0000),
        darkHC: RGBA(0.0745, 0.0784, 0.0902))
    /// Punteado del camino a pie.
    /// `walkColor (map.js)` · claro oklch(28.7% 0.007 285.9) = #2A2A2E · oscuro oklch(92.6% 0.005 286.3) = #E6E6EA
    static let mapWalk = DynamicColor(
        light: RGBA(0.1647, 0.1647, 0.1804),
        dark: RGBA(0.9020, 0.9020, 0.9176),
        lightHC: RGBA(0.1647, 0.1647, 0.1804),
        darkHC: RGBA(0.9020, 0.9020, 0.9176))

    // MARK: línea
    /// Gris de reserva cuando la API no manda color de línea (R57).
    /// `line.fallback` · claro oklch(55.3% 0.022 260.2) = #6B7380 · oscuro oklch(55.3% 0.022 260.2) = #6B7380
    static let lineFallback = DynamicColor(
        light: RGBA(0.4196, 0.4510, 0.5020),
        dark: RGBA(0.4196, 0.4510, 0.5020),
        lightHC: RGBA(0.4196, 0.4510, 0.5020),
        darkHC: RGBA(0.4196, 0.4510, 0.5020))
    // </generado:tokens>
}

/// La paleta que usan las vistas: un `Color` dinámico por token.
///
/// Cómo se elige:
/// - Texto: `ink` > `ink2` > `ink3` (principal, secundario, terciario).
/// - Superficies: `bg` (pantalla), `surface` (tarjeta opaca), `surfaceHi`
///   (ficha dentro de una tarjeta). El cristal no es un color: es
///   `.cristal(...)` (Glass.swift).
/// - El billete de minutos: `ticket` + `ticketInk` / `ticketInk2` /
///   `ticketWarn`. Invierte el tema: blanco en oscuro y negro en claro.
/// - Estados: el relleno (`warn`, `bad`, `ok`) nunca es color de texto; para
///   texto hay `warnText`, `badText`, `okText`, que sí pasan AA.
/// - Amarillo `via` solo para la vía confirmada. Nada más es amarillo.
enum Palette {
    // <generado:paleta>
    // Generado por design-lab/tools/tokens.mjs: un Color dinámico por token.

    // MARK: fondo
    /// Fondo de pantalla (debajo del mapa y de las listas).
    static let bg: Color = Tokens.bg.color
    /// Tarjeta OPACA (tramo, ruta, opción).
    static let surface: Color = Tokens.surface.color
    /// Ficha dentro de una tarjeta (salidas 2.ª–4.ª), campos, segmentos.
    static let surfaceHi: Color = Tokens.surfaceHi.color
    /// Filetes y separadores (con alfa).
    static let rule: Color = Tokens.rule.color

    // MARK: tinta
    /// Texto principal.
    static let ink: Color = Tokens.ink.color
    /// Texto secundario (dirección, destino de fichas, metadatos).
    static let ink2: Color = Tokens.ink2.color
    /// Texto terciario (rótulos de sección, pie, «min» de las fichas).
    static let ink3: Color = Tokens.ink3.color

    // MARK: cristal
    /// Relleno del cristal en iOS 17–25 (encima del material).
    static let glass: Color = Tokens.glass.color
    /// Brillo del canto superior del cristal (iOS 17–25).
    static let glassHighlight: Color = Tokens.glassHighlight.color
    /// Canto del cristal (1 pt).
    static let glassEdge: Color = Tokens.glassEdge.color
    /// Cristal con «Reducir transparencia»: compuesto opaco de --glass sobre el fondo.
    static let glassOpaque: Color = Tokens.glassOpaque.color

    // MARK: billete
    /// Fondo del billete: invierte el tema para que los minutos salten a contraluz.
    static let ticket: Color = Tokens.ticket.color
    /// Minutos y destino en el billete (AAA).
    static let ticketInk: Color = Tokens.ticketInk.color
    /// Unidad «min», hora y longitud en el billete.
    static let ticketInk2: Color = Tokens.ticketInk2.color
    /// Retraso dentro del billete.
    static let ticketWarn: Color = Tokens.ticketWarn.color
    /// Fondo de la etiqueta de ritmo «Anda» / «Con calma» (con alfa, sobre el billete).
    static let pace: Color = Tokens.pace.color

    // MARK: vía
    /// Caja sólida de la vía CONFIRMADA.
    static let via: Color = Tokens.via.color
    /// Texto dentro de la caja de vía (AAA).
    static let viaInk: Color = Tokens.viaInk.color
    /// Canto de 1 pt de la caja de vía, siempre.
    static let viaEdge: Color = Tokens.viaEdge.color

    // MARK: interacción
    /// Azul para texto e iconos interactivos (enlaces, pestaña activa, «Guardar»).
    static let accent: Color = Tokens.accent.color
    /// Relleno del botón principal con texto blanco (B daba 3,7:1).
    static let accentFill: Color = Tokens.accentFill.color
    /// Texto sobre accentFill y sobre bad.
    static let onAccent: Color = Tokens.onAccent.color

    // MARK: estado
    /// Perturbada: icono y fondo del aviso (con alfa).
    static let warn: Color = Tokens.warn.color
    /// Texto de aviso: «Perturbada», «+2 min», «cualquier sentido».
    static let warnText: Color = Tokens.warnText.color
    /// Fondo del aviso de línea perturbada (sobre la tarjeta).
    static let noticeWarn: Color = Tokens.noticeWarn.color
    /// Interrumpida / peligro: relleno de «Corre», del botón rojo y del banner de línea cortada (texto blanco encima).
    static let bad: Color = Tokens.bad.color
    /// Texto de error: «Interrumpida», «pasa por la línea cortada», «Eliminar ruta».
    static let badText: Color = Tokens.badText.color
    /// Fondo del aviso de línea interrumpida.
    static let noticeBad: Color = Tokens.noticeBad.color
    /// Relleno verde: billete «En andén», interruptores, punto «en directo» en oscuro.
    static let ok: Color = Tokens.ok.color
    /// Texto e iconos verdes (punto «en directo» y «listo» en claro; B daba 2,1:1).
    static let okText: Color = Tokens.okText.color
    /// Texto sobre el billete verde «En andén» (AAA).
    static let atStopInk: Color = Tokens.atStopInk.color

    // MARK: sombra
    /// Color base de las sombras (la opacidad va en cada sombra).
    static let shadow: Color = Tokens.shadow.color

    // MARK: mapa
    /// Contorno del trazado de la línea en el mapa.
    static let mapCasing: Color = Tokens.mapCasing.color
    /// Relleno de las paradas servidas.
    static let mapStopFill: Color = Tokens.mapStopFill.color
    /// Punteado del camino a pie.
    static let mapWalk: Color = Tokens.mapWalk.color

    // MARK: línea
    /// Gris de reserva cuando la API no manda color de línea (R57).
    static let lineFallback: Color = Tokens.lineFallback.color
    // </generado:paleta>
}
