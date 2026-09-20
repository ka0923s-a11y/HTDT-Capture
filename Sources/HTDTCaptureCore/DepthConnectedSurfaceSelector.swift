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

        let central = valid.filter {
            abs(Double($0.x) - centerX) <= halfWindowX
                && abs(Double($0.y) - centerY) <= halfWindowY
        }

        func centerDistanceSquared(
            _ sample: DepthGridSample
        ) -> Double {
            let dx = Double(sample.x) - centerX
            let dy = Double(sample.y) - centerY
            return dx * dx + dy * dy
        }

        let seed: DepthGridSample?
        if !central.isEmpty {
            seed = central.min {
                if abs($0.depthMeters - $1.depthMeters)
                    > 0.000_001
                {
                    return $0.depthMeters < $1.depthMeters
                }
                let lhsDistance = centerDistanceSquared($0)
                let rhsDistance = centerDistanceSquared($1)
                if abs(lhsDistance - rhsDistance) > 0.000_001 {
                    return lhsDistance < rhsDistance
                }
                if $0.y != $1.y {
                    return $0.y < $1.y
                }
                return $0.x < $1.x
            }
        } else {
            seed = valid.min {
                let lhsDistance = centerDistanceSquared($0)
                let rhsDistance = centerDistanceSquared($1)
                if abs(lhsDistance - rhsDistance) > 0.000_001 {
                    return lhsDistance < rhsDistance
                }
                if $0.depthMeters != $1.depthMeters {
                    return $0.depthMeters < $1.depthMeters
                }
                if $0.y != $1.y {
                    return $0.y < $1.y
                }
                return $0.x < $1.x
            }
        }

        guard let seed else {
            return valid
        }

        struct GridKey: Hashable {
            let x: Int
            let y: Int
        }

        var byKey: [GridKey: DepthGridSample] = [:]
        byKey.reserveCapacity(valid.count)
        for sample in valid {
            byKey[GridKey(x: sample.x, y: sample.y)] = sample
        }

        let seedKey = GridKey(x: seed.x, y: seed.y)
        var queue: [GridKey] = [seedKey]
        var visited: Set<GridKey> = [seedKey]
        var selected: [DepthGridSample] = []
        selected.reserveCapacity(valid.count)
        var cursor = 0

        while cursor < queue.count {
            let key = queue[cursor]
            cursor += 1
            guard let current = byKey[key] else {
                continue
            }
            selected.append(current)

            for dy in [-gridStepPixels, 0, gridStepPixels] {
                for dx in [-gridStepPixels, 0, gridStepPixels] {
                    if dx == 0 && dy == 0 {
                        continue
                    }
                    let neighborKey = GridKey(
                        x: key.x + dx,
                        y: key.y + dy
                    )
                    guard !visited.contains(neighborKey),
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

                    visited.insert(neighborKey)
                    queue.append(neighborKey)
                }
            }
        }

        guard selected.count >= minimumComponentCount else {
            return valid
        }

        return selected.sorted {
            if $0.y != $1.y {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }
    }
}
