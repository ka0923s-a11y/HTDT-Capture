import Foundation

public struct DepthGridSample: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let depthMeters: Double

    public init(
        x: Int,
        y: Int,
        depthMeters: Double
    ) {
        self.x = x
        self.y = y
        self.depthMeters = depthMeters
    }
}

public enum DepthConnectedSurfaceSelector {
    public static func selectForegroundConnectedComponent(
        samples: [DepthGridSample],
        imageWidth: Int,
        imageHeight: Int,
        gridStepPixels: Int,
        seedWindowFraction: Double = 0.18,
        minimumAbsoluteDepthDeltaMeters: Double = 0.14,
        relativeDepthDelta: Double = 0.06,
        minimumComponentCount: Int = 8
    ) -> [DepthGridSample] {
        guard imageWidth > 0,
              imageHeight > 0,
              gridStepPixels > 0,
              seedWindowFraction.isFinite,
              seedWindowFraction > 0,
              seedWindowFraction <= 0.5,
              minimumAbsoluteDepthDeltaMeters.isFinite,
              minimumAbsoluteDepthDeltaMeters > 0,
              relativeDepthDelta.isFinite,
              relativeDepthDelta >= 0,
              minimumComponentCount > 0
        else {
            return samples
        }

        let valid = samples.filter {
            $0.depthMeters.isFinite
                && $0.depthMeters > 0
        }
        guard valid.count >= minimumComponentCount else {
            return valid
        }

        let centerX = Double(imageWidth - 1) / 2
        let centerY = Double(imageHeight - 1) / 2
        let halfWindowX =
            Double(imageWidth) * seedWindowFraction
        let halfWindowY =
            Double(imageHeight) * seedWindowFraction

        func isCentral(
            _ sample: DepthGridSample
        ) -> Bool {
            abs(Double(sample.x) - centerX) <= halfWindowX
                && abs(Double(sample.y) - centerY) <= halfWindowY
        }

        func centerDistanceSquared(
            _ sample: DepthGridSample
        ) -> Double {
            let dx = Double(sample.x) - centerX
            let dy = Double(sample.y) - centerY
            return dx * dx + dy * dy
        }

        struct GridKey: Hashable, Comparable {
            let x: Int
            let y: Int

            static func < (lhs: GridKey, rhs: GridKey) -> Bool {
                if lhs.y != rhs.y {
                    return lhs.y < rhs.y
                }
                return lhs.x < rhs.x
            }
        }

        var byKey: [GridKey: DepthGridSample] = [:]
        byKey.reserveCapacity(valid.count)
        for sample in valid {
            byKey[GridKey(x: sample.x, y: sample.y)] = sample
        }

        func connectedComponent(
            from seed: GridKey,
            globallyVisited: inout Set<GridKey>
        ) -> [DepthGridSample] {
            var queue: [GridKey] = [seed]
            globallyVisited.insert(seed)
            var component: [DepthGridSample] = []
            var cursor = 0

            while cursor < queue.count {
                let key = queue[cursor]
                cursor += 1
                guard let current = byKey[key] else {
                    continue
                }
                component.append(current)

                for dy in [-gridStepPixels, 0, gridStepPixels] {
                    for dx in [-gridStepPixels, 0, gridStepPixels] {
                        if dx == 0 && dy == 0 {
                            continue
                        }
                        let neighborKey = GridKey(
                            x: key.x + dx,
                            y: key.y + dy
                        )
                        guard
                            !globallyVisited.contains(neighborKey),
                            let neighbor = byKey[neighborKey]
                        else {
                            continue
                        }

                        let allowedDelta = max(
                            minimumAbsoluteDepthDeltaMeters,
                            min(
                                current.depthMeters,
                                neighbor.depthMeters
                            ) * relativeDepthDelta
                        )
                        guard abs(
                            current.depthMeters
                                - neighbor.depthMeters
                        ) <= allowedDelta
                        else {
                            continue
                        }

                        globallyVisited.insert(neighborKey)
                        queue.append(neighborKey)
                    }
                }
            }

            return component
        }

        var visited: Set<GridKey> = []
        var components: [[DepthGridSample]] = []

        for key in byKey.keys.sorted() {
            guard !visited.contains(key) else {
                continue
            }
            let component = connectedComponent(
                from: key,
                globallyVisited: &visited
            )
            if component.count >= minimumComponentCount {
                components.append(component)
            }
        }

        guard !components.isEmpty else {
            return valid
        }

        func componentScore(
            _ component: [DepthGridSample]
        ) -> (
            foreground: Double,
            centralCount: Int,
            count: Int,
            nearestCenter: Double,
            meanDepth: Double
        ) {
            let centralCount =
                component.filter(isCentral).count
            let meanDepth =
                component.map(\.depthMeters).reduce(0, +)
                / Double(component.count)
            let nearestCenter =
                component.map(centerDistanceSquared).min()
                ?? Double.greatestFiniteMagnitude

            // Favor a substantial component visible near the center while
            // still preferring foreground furniture over a larger far wall.
            // Tiny foreground clutter therefore cannot win on depth alone.
            let foreground =
                Double(centralCount) / max(meanDepth, 0.05)
                + 0.05 * sqrt(Double(component.count))

            return (
                foreground,
                centralCount,
                component.count,
                nearestCenter,
                meanDepth
            )
        }

        let selected = components.max { lhs, rhs in
            let a = componentScore(lhs)
            let b = componentScore(rhs)

            if abs(a.foreground - b.foreground) > 0.000_001 {
                return a.foreground < b.foreground
            }
            if a.centralCount != b.centralCount {
                return a.centralCount < b.centralCount
            }
            if a.count != b.count {
                return a.count < b.count
            }
            if abs(a.nearestCenter - b.nearestCenter) > 0.000_001 {
                return a.nearestCenter > b.nearestCenter
            }
            return a.meanDepth > b.meanDepth
        } ?? valid

        return selected.sorted {
            if $0.y != $1.y {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }
    }
}
