import Foundation

/// Variantes de un destino, de la más completa a la más corta, sin cortar
/// nunca una palabra (docs/diseno/decisiones-la-widgets.md §7).
///
/// Es el `abreviar()` del laboratorio (design-lab/b-cristal-v2/app.js)
/// pasado a Swift, con las mismas reglas y el mismo orden. La app calcula las
/// variantes y la vista se queda con la primera que cabe (`ViewThatFits` con
/// un `Text` por variante y `lineLimit(1)`); si no cabe ninguna, se quita el
/// destino entero. Nunca «Ermont - Eaub…».
///
/// Reglas, en orden (cada una solo aporta una variante si queda más corta):
/// 1. Completo, normalizado (espacios dobles, guiones largos).
/// 2. Compactar sin perder nada: « - » → «-», fuera los paréntesis, fuera
///    «Paris » delante de otro nombre y «Gare » delante de un nombre propio
///    («Gare de Lyon» y «Gare du Nord» se quedan: «Lyon» o «Nord» solos
///    confunden).
/// 3. Diccionario de la señalética, en palabras enteras (también dentro de un
///    compuesto): Saint → St, Porte → Pte, Aéroport → Aérop., Charles de
///    Gaulle → CDG…
/// 4. La parte principal de un nombre doble SNCF («A - B» → «A»).
/// 5. El alias corto de siempre (cómo se dice en el andén).
enum DestinationAbbreviator {

    /// Las variantes, de la más larga a la más corta. Vacío si no hay nombre.
    static func variants(_ destination: String) -> [String] {
        var out: [String] = []
        func push(_ value: String) {
            let v = normalizeSpaces(value)
            guard !v.isEmpty, !out.contains(v) else { return }
            if let last = out.last, v.count >= last.count { return }
            out.append(v)
        }

        let full = normalizeSpaces(
            destination
                .precomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-"))
        guard !full.isEmpty else { return [] }
        push(full)

        // 2 · Compactar sin perder nada.
        var compact = replacing(full, pattern: #"\s*\([^)]*\)"#, with: "")
        compact = replacing(compact, pattern: #"\s+-\s+"#, with: "-")
        compact = stripLeadingWords(compact)
        push(compact)

        // 3 · Abreviaturas en palabras enteras.
        push(applyDictionary(compact))

        // 4 · La parte principal de «A - B» (solo el guion con espacios del
        // original, no el de «Saint-Lazare»).
        if full.contains(" - ") {
            let main = full.components(separatedBy: " - ").first ?? full
            var part = replacing(main, pattern: #"\s*\([^)]*\)"#, with: "")
            part = stripLeadingWords(part)
            push(applyDictionary(part))
        }

        // 5 · Alias corto.
        if let alias = shortNames[full] { push(alias) }
        return out
    }

    /// La más corta de las variantes (la que va en las fichas con mezcla de
    /// destinos), o nil si no hay nombre.
    static func shortest(_ destination: String) -> String? {
        variants(destination).last
    }

    /// La variante número `level`, o la más corta si no hay tantas. Sirve
    /// para que todo un widget use el mismo nivel de abreviatura.
    static func variant(_ variants: [String], level: Int) -> String? {
        guard !variants.isEmpty else { return nil }
        return variants[min(max(0, level), variants.count - 1)]
    }

    // MARK: - Reglas

    /// Diccionario de la señalética RATP/SNCF. Se aplica en orden y solo a
    /// palabras enteras: una letra (con o sin tilde) a cualquier lado impide
    /// el cambio, un guion o un espacio no.
    static let dictionary: [(word: String, abbreviation: String)] = [
        ("Saintes", "Stes"), ("Saints", "Sts"), ("Sainte", "Ste"), ("Saint", "St"),
        ("Porte", "Pte"), ("Place", "Pl."), ("Pont", "Pt"), ("Château", "Chât."),
        ("Université", "Univ."), ("Aéroport", "Aérop."), ("Charles[ -]de[ -]Gaulle", "CDG"),
        ("Avenue", "Av."), ("Boulevard", "Bd"), ("Faubourg", "Fg"), ("Terminal", "T"),
    ]

    /// Cómo se dice en el andén. La clave es el nombre completo normalizado.
    static let shortNames: [String: String] = [
        "Saint-Denis Pleyel": "Pleyel",
        "Marne-la-Vallée Chessy": "Chessy",
        "Aéroport Charles de Gaulle 2 TGV": "CDG 2",
        "Aéroport Charles de Gaulle 1": "CDG 1",
        "Saint-Rémy-lès-Chevreuse": "St-Rémy",
        "Saint-Germain-en-Laye": "St-Germain",
        "Saint-Quentin-en-Yvelines": "St-Quentin",
        "Boissy-Saint-Léger": "Boissy",
        "Mantes-la-Jolie": "Mantes",
        "Versailles Château Rive Gauche": "Versailles RG",
        "Cergy-le-Haut": "Cergy",
        "Mairie de Montrouge": "Montrouge",
        "Pont de Bezons": "Bezons",
    ]

    private static func applyDictionary(_ text: String) -> String {
        var result = text
        for entry in dictionary {
            // Palabra entera con letras de cualquier alfabeto (\b no ve la
            // «é» como letra y «Université» no se abreviaría).
            let pattern = #"(?<!\p{L})"# + entry.word + #"(?!\p{L})"#
            result = replacing(result, pattern: pattern, with: entry.abbreviation)
        }
        return result
    }

    /// Fuera «Paris » delante de otro nombre y «Gare » delante de un nombre
    /// propio (no delante de «de», «du», «d'» ni «des»).
    private static func stripLeadingWords(_ text: String) -> String {
        var result = replacing(text, pattern: #"^Paris\s+(?=\S)"#, with: "")
        result = replacing(result, pattern: #"^Gare\s+(?!de\b|du\b|d'|d’|des\b)"#, with: "")
        return result
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    private static func normalizeSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
