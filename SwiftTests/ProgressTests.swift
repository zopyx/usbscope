import XCTest
@testable import UsbScopeCore
import UsbScopeUI

/// The loading line: the app promises a three-state UI (idle → loading → loaded)
/// with progress *per call*, so every stage of a `collect` has to be nameable
/// before the collection is over.
final class ProgressTests: XCTestCase {
    /// The stage name is the OS source being read; those names are technical and
    /// stay English in both languages.
    func testStageNamesAreTheTechnicalIdentifiers() {
        XCTAssertEqual(ProgressPresentation.stageName(.ports), "Ports")
        XCTAssertEqual(ProgressPresentation.stageName(.buses), "Buses")
        XCTAssertEqual(ProgressPresentation.stageName(.thunderbolt), "Thunderbolt")
        XCTAssertEqual(ProgressPresentation.stageName(.hardware), "Hardware")
        XCTAssertEqual(ProgressPresentation.stageName(.charging), "Charging")
        XCTAssertEqual(ProgressPresentation.stageName(.registry), "Registry")
    }

    /// Every stage the builder can report must have a name — a new case would
    /// otherwise render as an empty word in the status line.
    func testEveryStageHasANonEmptyName() {
        for stage in SnapshotStage.allCases {
            XCTAssertFalse(
                ProgressPresentation.stageName(stage).isEmpty,
                "\(stage.rawValue) has no name"
            )
        }
    }

    /// Before the first callback the line must still say something useful.
    func testNoProgressYetStillProducesALine() {
        XCTAssertEqual(
            ProgressPresentation.text(nil, verb: "collecting"), "collecting …"
        )
        XCTAssertEqual(ProgressPresentation.text(nil, verb: "sammle"), "sammle …")
    }

    /// `index` is 1-based and `total` is the stage count, so the pair reads as a
    /// counter the user can follow.
    func testTextCarriesTheStageAndTheCounter() {
        let progress = SnapshotProgress(stage: .charging, index: 5, total: 6)
        XCTAssertEqual(
            ProgressPresentation.text(progress, verb: "collecting"), "collecting Charging · 5/6"
        )
        XCTAssertEqual(
            ProgressPresentation.text(progress, verb: "sammle"), "sammle Charging · 5/6"
        )
        // The counter and the stage are both present, whatever the verb.
        let line = ProgressPresentation.text(progress, verb: "sammle")
        XCTAssertTrue(line.contains("Charging"))
        XCTAssertTrue(line.contains("5/6"))
    }

    /// The bar is determinate: the first stage is not already full, the last one is.
    func testFractionSpansTheRun() {
        let first = SnapshotProgress(stage: .ports, index: 1, total: 6)
        XCTAssertEqual(first.fraction, 1.0 / 6.0, accuracy: 0.0001)
        let last = SnapshotProgress(stage: .registry, index: 6, total: 6)
        XCTAssertEqual(last.fraction, 1.0, accuracy: 0.0001)
    }

    /// A total of zero would divide by zero: report "no progress", not a crash.
    func testUnknownTotalIsNotAFailure() {
        let progress = SnapshotProgress(stage: .ports, index: 1, total: 0)
        XCTAssertEqual(progress.fraction, 0)
    }

    /// The line the app shows is built from the stage the builder reported, in the
    /// same order — this is what makes the per-call progress visible.
    func testReportedStagesRenderInOrder() {
        var lines: [String] = []
        _ = SnapshotBuilder.collect(progress: { stage, index, total in
            lines.append(
                ProgressPresentation.text(
                    SnapshotProgress(stage: stage, index: index, total: total),
                    verb: "collecting"
                )
            )
        })
        XCTAssertEqual(lines.count, SnapshotStage.allCases.count)
        let total = SnapshotStage.allCases.count
        XCTAssertTrue(
            lines.first?.hasPrefix("collecting Ports · 1/\(total)") == true, lines.first ?? "–"
        )
        XCTAssertTrue(lines.last?.hasSuffix("· \(total)/\(total)") == true, lines.last ?? "–")
    }
}
