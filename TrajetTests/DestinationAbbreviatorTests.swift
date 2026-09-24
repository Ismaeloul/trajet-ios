import XCTest
@testable import Trajet

/// El destino nunca se corta a mitad de palabra: variantes de la más completa
/// a la más corta (docs/diseno/decisiones-la-widgets.md §7, `abreviar()` del
/// laboratorio).
final class DestinationAbbreviatorTests: XCTestCase {

    // MARK: - Los ejemplos del laboratorio

    func testErmontEaubonne() {
        XCTAssertEqual(DestinationAbbreviator.variants("Ermont - Eaubonne"),
                       ["Ermont - Eaubonne", "Ermont-Eaubonne", "Ermont"])
    }

    func testGareSaintLazare() {
        XCTAssertEqual(DestinationAbbreviator.variants("Gare Saint-Lazare"),
                       ["Gare Saint-Lazare", "Saint-Lazare", "St-Lazare"])
    }

    func testSaintDenisPleyel() {
        XCTAssertEqual(DestinationAbbreviator.variants("Saint-Denis Pleyel"),
                       ["Saint-Denis Pleyel", "St-Denis Pleyel", "Pleyel"])
    }

    func testAeropuertoCDG2() {
        XCTAssertEqual(DestinationAbbreviator.variants("Aéroport Charles de Gaulle 2 TGV"),
                       ["Aéroport Charles de Gaulle 2 TGV", "Aérop. CDG 2 TGV", "CDG 2"])
    }

    func testPontDeBezons() {
        XCTAssertEqual(DestinationAbbreviator.variants("Pont de Bezons"),
                       ["Pont de Bezons", "Pt de Bezons", "Bezons"])
    }

    func testSaintRemyLesChevreuse() {
        XCTAssertEqual(DestinationAbbreviator.variants("Saint-Rémy-lès-Chevreuse"),
                       ["Saint-Rémy-lès-Chevreuse", "St-Rémy-lès-Chevreuse", "St-Rémy"])
    }

    /// «Gare de Lyon» y «Gare du Nord» se quedan: «Lyon» o «Nord» solos confunden.
    func testGareDeLyonSinVariantes() {
        XCTAssertEqual(DestinationAbbreviator.variants("Gare de Lyon"), ["Gare de Lyon"])
        XCTAssertEqual(DestinationAbbreviator.variants("Gare du Nord"), ["Gare du Nord"])
    }

    // MARK: - Reglas

    func testNombreDobleConPalabraAbreviada() {
        XCTAssertEqual(DestinationAbbreviator.variants("Saint-Denis - Université"),
                       ["Saint-Denis - Université", "Saint-Denis-Université", "St-Denis-Univ.", "St-Denis"])
        XCTAssertEqual(DestinationAbbreviator.variants("Châtillon - Montrouge"),
                       ["Châtillon - Montrouge", "Châtillon-Montrouge", "Châtillon"])
        XCTAssertEqual(DestinationAbbreviator.variants("Gallieni - Pont de Bondy"),
                       ["Gallieni - Pont de Bondy", "Gallieni-Pont de Bondy", "Gallieni-Pt de Bondy", "Gallieni"])
    }

    func testParentesisYParisFuera() {
        XCTAssertEqual(DestinationAbbreviator.variants("La Défense (Grande Arche)"),
                       ["La Défense (Grande Arche)", "La Défense"])
        XCTAssertEqual(DestinationAbbreviator.variants("Paris Saint-Lazare"),
                       ["Paris Saint-Lazare", "Saint-Lazare", "St-Lazare"])
    }

    func testDiccionarioSoloEnPalabrasEnteras() {
        // «Pontoise» no es «Pont», «Portes» no es «Porte».
        XCTAssertEqual(DestinationAbbreviator.variants("Pontoise"), ["Pontoise"])
        XCTAssertEqual(DestinationAbbreviator.variants("Porte de Versailles"),
                       ["Porte de Versailles", "Pte de Versailles"])
        XCTAssertEqual(DestinationAbbreviator.variants("Boissy-Saint-Léger"),
                       ["Boissy-Saint-Léger", "Boissy-St-Léger", "Boissy"])
    }

    func testNormalizaEspaciosYGuionesLargos() {
        XCTAssertEqual(DestinationAbbreviator.variants("  Ermont  –  Eaubonne "),
                       ["Ermont - Eaubonne", "Ermont-Eaubonne", "Ermont"])
    }

    func testVacioNoDaVariantes() {
        XCTAssertEqual(DestinationAbbreviator.variants(""), [])
        XCTAssertEqual(DestinationAbbreviator.variants("   "), [])
        XCTAssertNil(DestinationAbbreviator.shortest(""))
    }

    /// Cada variante es más corta que la anterior, no se repite, no lleva
    /// «…» y está hecha de palabras enteras del nombre (o de su abreviatura).
    func testNuncaCortaPalabras() {
        let names = ["Ermont - Eaubonne", "Aéroport Charles de Gaulle 2 TGV", "Saint-Rémy-lès-Chevreuse",
                     "Mantes-la-Jolie", "Versailles Château Rive Gauche", "Marne-la-Vallée Chessy",
                     "Châtelet - Les Halles", "Gallieni - Pont de Bondy", "Saint-Quentin-en-Yvelines",
                     "Boulevard Victor", "Faubourg Saint-Antoine", "Place d'Italie"]
        for name in names {
            let variants = DestinationAbbreviator.variants(name)
            XCTAssertFalse(variants.isEmpty, name)
            XCTAssertEqual(variants.first, name, name)
            for (a, b) in zip(variants, variants.dropFirst()) {
                XCTAssertLessThan(b.count, a.count, "\(name): «\(b)» no es más corta que «\(a)»")
            }
            XCTAssertEqual(Set(variants).count, variants.count, name)
            for v in variants {
                XCTAssertFalse(v.contains("…"), v)
                XCTAssertEqual(v, v.trimmingCharacters(in: .whitespaces), v)
            }
        }
    }

    func testVarianteDeUnNivel() {
        let v = DestinationAbbreviator.variants("Ermont - Eaubonne")
        XCTAssertEqual(DestinationAbbreviator.variant(v, level: 0), "Ermont - Eaubonne")
        XCTAssertEqual(DestinationAbbreviator.variant(v, level: 2), "Ermont")
        XCTAssertEqual(DestinationAbbreviator.variant(v, level: 9), "Ermont")    // la más corta
        XCTAssertEqual(DestinationAbbreviator.variant(v, level: -1), "Ermont - Eaubonne")
        XCTAssertNil(DestinationAbbreviator.variant([], level: 0))
        XCTAssertEqual(DestinationAbbreviator.variants(v, from: 1), ["Ermont-Eaubonne", "Ermont"])
        XCTAssertEqual(DestinationAbbreviator.variants(v, from: 7), ["Ermont"])
        XCTAssertEqual(DestinationAbbreviator.shortest("Mantes-la-Jolie"), "Mantes")
    }

    /// Un solo nivel por widget: si la cabecera necesita «Ermont», las filas
    /// también dicen «Ermont» aunque cupiera más.
    func testNivelComunDelWidget() {
        let head = DestinationAbbreviator.variants("Ermont - Eaubonne")
        let row = DestinationAbbreviator.variants("Mantes-la-Jolie")
        typealias Slot = DestinationAbbreviator.Slot
        // Todo cabe: nivel 0.
        XCTAssertEqual(DestinationAbbreviator.sharedLevel([Slot(variants: head, room: 300, size: 14),
                                                           Slot(variants: row, room: 300, size: 12)]), 0)
        // La cabecera del mediano (≈ 96 pt) solo admite «Ermont»: nivel 2 para todos.
        XCTAssertEqual(DestinationAbbreviator.sharedLevel([Slot(variants: head, room: 96, size: 14),
                                                           Slot(variants: row, room: 300, size: 12)]), 2)
        // Nada cabe: el nivel más profundo (cada vista sigue cayendo sola).
        XCTAssertEqual(DestinationAbbreviator.sharedLevel([Slot(variants: head, room: 1, size: 14)]), 2)
        XCTAssertEqual(DestinationAbbreviator.sharedLevel([]), 0)
    }
}
