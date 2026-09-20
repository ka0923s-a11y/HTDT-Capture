import XCTest
@testable import HTDTCaptureCore

final class DepthConnectedSurfaceSelectorTests: XCTestCase {
    func testSelectsCentralForegroundComponent() {
        let foreground = grid(
            originX: 40,
            originY: 40,
            width: 3,
            height: 3,
            step: 10,
            depth: 1.1
        )
        let background = grid(
            originX: 0,
            originY: 0,
            width: 4,
            height: 4,
            step: 10,
            depth: 3.0
        )

        let selected =
            DepthConnectedSurfaceSelector
                .selectForegroundConnectedComponent(
                    samples: foreground + background,
                    imageWidth: 100,
                    imageHeight: 100,
                    gridStepPixels: 10,
                    minimumComponentCount: 8
                )

        XCTAssertEqual(Set(selected), Set(foreground))
    }

    func testFragmentedDepthDoesNotFallBackToWholeCrop() {
        let samples = [
            DepthGridSample(x: 20, y: 20, depthMeters: 1.0),
            DepthGridSample(x: 40, y: 20, depthMeters: 1.1),
            DepthGridSample(x: 60, y: 20, depthMeters: 1.2),
            DepthGridSample(x: 80, y: 20, depthMeters: 1.3),
            DepthGridSample(x: 20, y: 60, depthMeters: 2.0),
            DepthGridSample(x: 40, y: 60, depthMeters: 2.1),
            DepthGridSample(x: 60, y: 60, depthMeters: 2.2),
            DepthGridSample(x: 80, y: 60, depthMeters: 2.3),
        ]

        let selected =
            DepthConnectedSurfaceSelector
                .selectForegroundConnectedComponent(
                    samples: samples,
                    imageWidth: 100,
                    imageHeight: 100,
                    gridStepPixels: 10,
                    minimumComponentCount: 8
                )

        XCTAssertTrue(selected.isEmpty)
    }

    func testInsufficientSamplesReturnNoFocusedTarget() {
        let samples = grid(
            originX: 40,
            originY: 40,
            width: 2,
            height: 3,
            step: 10,
            depth: 1.0
        )

        let selected =
            DepthConnectedSurfaceSelector
                .selectForegroundConnectedComponent(
                    samples: samples,
                    imageWidth: 100,
                    imageHeight: 100,
                    gridStepPixels: 10,
                    minimumComponentCount: 8
                )

        XCTAssertTrue(selected.isEmpty)
    }

    private func grid(
        originX: Int,
        originY: Int,
        width: Int,
        height: Int,
        step: Int,
        depth: Double
    ) -> [DepthGridSample] {
        (0..<height).flatMap { row in
            (0..<width).map { column in
                DepthGridSample(
                    x: originX + column * step,
                    y: originY + row * step,
                    depthMeters: depth
                )
            }
        }
    }
}
