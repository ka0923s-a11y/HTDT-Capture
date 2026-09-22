import Foundation
import SwiftUI
import HTDTCaptureCore
#if canImport(ImageIO)
import ImageIO
#endif

/// Bounded decode cache for library-row previews (issue #411). A
/// thumbnail is disposable derived data — never authority: rows ask
/// for it lazily, misses are remembered so a re-render never
/// re-reads, and `NSCache` caps how many decodes stay resident.
public final class SeriesThumbnailCache: @unchecked Sendable {
    /// A cached decode. `image == nil` is a negative hit — the
    /// series retains no readable preview and must not be re-scanned
    /// on every re-render.
    private final class Entry: Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()
    private let maxPixelSize: Int

    public init(limit: Int = 64, maxPixelSize: Int = 160) {
        cache.countLimit = limit
        self.maxPixelSize = maxPixelSize
    }

    /// Representative image for one series row, or nil when no
    /// revision retains a readable preview. The file/archive read and
    /// the decode run off the caller's executor; candidates are tried
    /// in `representativePreviewCandidates` order — the presented
    /// head first, then the most recent revision that still carries
    /// a preview.
    public func thumbnail(
        for group: CaptureSeriesGroup
    ) async -> CGImage? {
        let key = Self.key(for: group) as NSString
        if let entry = cache.object(forKey: key) {
            return entry.image
        }
        let pixelSize = maxPixelSize
        let image = await Task.detached(priority: .utility) {
            Self.decodeRepresentativePreview(
                candidates: group.representativePreviewCandidates,
                maxPixelSize: pixelSize
            )
        }.value
        guard !Task.isCancelled else { return image }
        cache.setObject(Entry(image), forKey: key)
        return image
    }

    /// Disposable: drop every decoded entry — e.g. when the persisted
    /// inventory changes underneath the library.
    public func removeAll() {
        cache.removeAllObjects()
    }

    /// Series identity plus the revision whose preview is tried
    /// first (presented head when it resolves, else the newest), so
    /// a re-scan or a head switch re-reads rather than serving a
    /// stale preview.
    static func key(for group: CaptureSeriesGroup) -> String {
        let head =
            (group.preferredRevision ?? group.latestRevision)?
            .captureRevisionID.description
            ?? "empty"
        return "\(group.captureSeriesID.description)#\(head)"
    }

    private static func decodeRepresentativePreview(
        candidates: [PersistedCaptureRecord],
        maxPixelSize: Int
    ) -> CGImage? {
        for record in candidates {
            if Task.isCancelled { return nil }
            guard let data = record.representativePreviewData() else {
                continue
            }
            if let image = decodeThumbnail(
                data: data,
                maxPixelSize: maxPixelSize
            ) {
                return image
            }
        }
        return nil
    }

    /// Bounded HEIC→CGImage decode via ImageIO — identical on iOS and
    /// macOS. nil for undecodable payloads so the caller moves to the
    /// next candidate.
    static func decodeThumbnail(
        data: Data,
        maxPixelSize: Int
    ) -> CGImage? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        )
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
        #else
        return nil
        #endif
    }
}

/// One library-row preview (issue #411): a representative frame of
/// the newest preview-bearing revision, loaded off the main actor
/// into a fixed 40pt tile — stable row geometry while loading,
/// aspect-fill crop once decoded, and the semantic placeholder
/// whenever the series retains no preview. Decorative only: the row
/// reads its title, never the image.
struct SeriesThumbnailView: View {
    let group: CaptureSeriesGroup
    let cache: SeriesThumbnailCache

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "house")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .background(
            .quaternary,
            in: RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
        .task(id: SeriesThumbnailCache.key(for: group)) {
            image = await cache.thumbnail(for: group)
        }
    }
}
