import XCTest
@testable import Trajet

/// El último tablero en disco con su hora de llegada (R20, R9).
final class BoardCacheTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("trajet-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// R20: guardar, esperar y recargar devuelve la hora real de llegada; la
    /// antigüedad incluye el tiempo en disco.
    func testRestauraHoraDeLlegada() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let url = dir.appendingPathComponent("last-board.json")
        let original = PreviewData.board(.tranquilo)
        XCTAssertTrue(BoardCache.save(CachedBoard(board: original, receivedAt: t0, routeID: 4), to: url))

        let loaded = try XCTUnwrap(BoardCache.load(from: url))
        XCTAssertEqual(loaded.receivedAt, t0)
        XCTAssertEqual(loaded.board.receivedAt, t0)      // nunca «recién hecho»
        XCTAssertEqual(loaded.routeID, 4)
        XCTAssertEqual(loaded.board.legs, original.legs)
        XCTAssertEqual(loaded.board.ageSeconds(now: t0.addingTimeInterval(600)), 600 + original.dataAge, accuracy: 0.001)
        XCTAssertTrue(loaded.board.isStale(now: t0.addingTimeInterval(600)))
    }

    /// Lo nuevo de la v1 sobrevive al disco (lo leen los widgets).
    func testConservaCamposV1() throws {
        let url = dir.appendingPathComponent("b.json")
        let original = PreviewData.board(.casosLimite)
        BoardCache.save(CachedBoard(board: original, receivedAt: Date(timeIntervalSinceReferenceDate: 1), routeID: nil), to: url)
        let loaded = try XCTUnwrap(BoardCache.load(from: url))
        XCTAssertNil(loaded.routeID)
        XCTAssertEqual(loaded.board.server, original.server)
        XCTAssertFalse(loaded.board.disruptionsOK)
        XCTAssertEqual(loaded.board.legs.map(\.fromId), original.legs.map(\.fromId))
        XCTAssertEqual(loaded.board.legs.map(\.platformExpected), original.legs.map(\.platformExpected))
        XCTAssertNil(loaded.board.legs[3].age)
    }

    /// El fichero en disco tiene la forma de la API (snake_case) y la fecha.
    func testFormatoEnDisco() throws {
        let url = dir.appendingPathComponent("c.json")
        BoardCache.save(CachedBoard(board: PreviewData.board(.unTramo), receivedAt: Date(), routeID: 5), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"received_at\""))
        XCTAssertTrue(text.contains("\"route_id\""))
        XCTAssertTrue(text.contains("\"platform_expected\""))
        XCTAssertTrue(text.contains("\"disruptions_ok\""))
    }

    func testSinFicheroOFicheroRoto() throws {
        XCTAssertNil(BoardCache.load(from: dir.appendingPathComponent("no-existe.json")))
        let broken = dir.appendingPathComponent("roto.json")
        try Data("{\"board\": 3".utf8).write(to: broken)
        XCTAssertNil(BoardCache.load(from: broken))
    }

    /// Hay siempre un sitio donde guardar (App Group o Application Support).
    func testHayDondeGuardar() {
        XCTAssertNotNil(BoardCache.fileURL)
        XCTAssertNotNil(BoardCache.localFileURL)
        XCTAssertEqual(BoardCache.fileURL?.lastPathComponent, "last-board.json")
    }
}
