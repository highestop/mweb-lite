import Foundation
import XCTest
import CaseReporting
@testable import MWebLite

final class DrawerGeometryTests: CaseReportingTestCase {
    func test_DRAWER_001_ColumnsSlideTogetherWhileDetailKeepsItsRightEdge() {
        // Given: normal, resized, and extremely narrow windows with requested column widths.
        let scenarios: [(width: CGFloat, category: CGFloat, article: CGFloat,
                         expectedCategory: CGFloat, expectedArticle: CGFloat)] = [
            (1180, 180, 400, 180, 400),
            (1380, 215, 360, 215, 360),
            (1380, -10, -10, 180, 320),
            (1380, 999, 999, 280, 400),
            (940, 180, 400, 180, 340),
            (940, 280, 400, 200, 320),
            (920, 280, 400, 180, 320),
            (850, 280, 400, 154.8, 275.2),
            (820, 280, 400, 144, 256),
            (700, 280, 400, 100.8, 179.2),
            (420, 280, 400, 0, 0),
            (400, 280, 400, 0, 0),
            (0, 280, 400, 0, 0)
        ]
        let overlap: CGFloat = 16
        let height: CGFloat = 850
        let accuracy: CGFloat = 0.000_001
        let progressValues: [CGFloat] = [0, 0.125, 0.5, 0.875, 1, 0.625, 0.25, 0]

        for scenario in scenarios {
            let size = CGSize(width: scenario.width, height: height)
            var previous: DrawerGeometry?

            // When: sample opening, reversing direction, and closing the same mounted layout.
            for progress in progressValues {
                let geometry = DrawerGeometry(size: size, progress: progress,
                                              categoryWidth: scenario.category, articleWidth: scenario.article)
                let context = "Window \(scenario.width), requested \(scenario.category)/\(scenario.article), progress \(progress)"

                // Then: column widths remain constant, and the document's right edge never moves.
                XCTAssertEqual(geometry.categoryWidth, scenario.expectedCategory, accuracy: accuracy, context)
                XCTAssertEqual(geometry.articleWidth, scenario.expectedArticle, accuracy: accuracy, context)
                XCTAssertEqual(geometry.categoryFrame.width, scenario.expectedCategory, accuracy: accuracy, context)
                XCTAssertEqual(geometry.articleFrame.width - overlap, scenario.expectedArticle, accuracy: accuracy, context)
                XCTAssertEqual(geometry.detailFrame.maxX, scenario.width, accuracy: accuracy, context)
                let drawerWidth = scenario.expectedCategory + scenario.expectedArticle
                XCTAssertEqual(geometry.detailFrame.minX + overlap, progress * drawerWidth, accuracy: accuracy, context)
                XCTAssertEqual(geometry.categoryDividerX, geometry.categoryFrame.maxX, accuracy: accuracy, context)
                XCTAssertEqual(geometry.articleDividerX, geometry.articleFrame.maxX, accuracy: accuracy, context)
                XCTAssertEqual(geometry.articleFrame.minX + overlap, geometry.categoryFrame.maxX, accuracy: accuracy, context)
                XCTAssertEqual(geometry.detailFrame.minX + overlap, geometry.articleFrame.maxX, accuracy: accuracy, context)
                XCTAssertGreaterThanOrEqual(geometry.detailFrame.width - overlap, min(420, scenario.width) - accuracy, context)

                for frame in [geometry.categoryFrame, geometry.articleFrame, geometry.detailFrame] {
                    XCTAssertTrue(frame.minX.isFinite && frame.width.isFinite, context)
                    XCTAssertGreaterThanOrEqual(frame.width, 0, context)
                    XCTAssertEqual(frame.minY, 0, accuracy: accuracy, context)
                    XCTAssertEqual(frame.height, height, accuracy: accuracy, context)
                }
                if let previous {
                    let slide = geometry.categoryFrame.minX - previous.categoryFrame.minX
                    XCTAssertEqual(geometry.articleFrame.minX - previous.articleFrame.minX, slide, accuracy: accuracy, context)
                    XCTAssertEqual(geometry.detailFrame.minX - previous.detailFrame.minX, slide, accuracy: accuracy, context)
                }
                if progress == 0 {
                    XCTAssertLessThanOrEqual(geometry.categoryFrame.maxX, accuracy, context)
                    XCTAssertEqual(geometry.articleFrame.maxX, 0, accuracy: accuracy, context)
                    XCTAssertEqual(geometry.detailFrame.minX + overlap, 0, accuracy: accuracy, context)
                } else if progress == 1 {
                    XCTAssertEqual(geometry.categoryFrame.minX, 0, accuracy: accuracy, context)
                    XCTAssertEqual(geometry.articleDividerX, drawerWidth, accuracy: accuracy, context)
                }
                previous = geometry
            }
        }
    }
}
