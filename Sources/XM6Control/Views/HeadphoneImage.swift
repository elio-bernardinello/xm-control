import SwiftUI
import AppKit
import ImageIO
import SonyHeadphonesKit

/// One shared, decoded photo for the window, menu and compact panel.
/// Custom images can be refreshed explicitly through `HeadphoneImageCache.reload()`;
/// there is no filesystem polling or disk access during SwiftUI body evaluation.
struct HeadphoneImage: View {
    @ObservedObject private var cache = HeadphoneImageCache.shared

    var body: some View {
        if let image = cache.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            HeadphoneIllustration()
        }
    }
}

final class HeadphoneImageCache: ObservableObject {
    static let shared = HeadphoneImageCache()
    @Published private(set) var image: NSImage?

    private init() { reload() }

    /// Call on the main thread after importing a replacement photo.
    func reload() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let model = UserDefaults.standard.string(forKey: "lastHeadsetModel").flatMap(HeadsetModel.init(rawValue:))
        // Per-generation photos, newest first: a user-provided file in
        // Application Support wins, then the bundled photo, then the generic
        // vector illustration. XM4 ships without a bundled photo.
        var names: [String] = []
        if let model {
            names += ["WH-1000\(model.rawValue)", model.rawValue.lowercased()]
        }
        names += ["WH-1000XM6", "xm6", "WH-1000XM5", "xm5", "WH-1000XM4", "xm4", "headphones"]
        var locations: [URL?] = support.map { base in
            names.map { base.appendingPathComponent("XM Control/\($0).png") }
        }.flatMap { $0 } ?? []
        locations += [
            support?.appendingPathComponent("XM6 Control/headphones.png"),
        ]
        locations += names.compactMap { Bundle.main.url(forResource: $0, withExtension: "png") }
        image = locations.compactMap { $0 }.lazy.compactMap { url -> NSImage? in
            // Decode once, rather than letting NSImage repeatedly defer file reads. No
            // view shows the photo above 170 pt today, so a 1024 px bitmap is kept
            // instead of the 2000 px source; the logical size stays the photo's own.
            guard let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1024,
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: thumbnail, size: representation.size)
        }.first
    }
}

/// Vector fallback when no photo is bundled. The open-source build ships no
/// Sony product photo; users may drop their own `headphones.png` into
/// `~/Library/Application Support/XM Control/` and it will be used instead.
struct HeadphoneIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)

            ZStack {
                // Headband (outer)
                HeadbandArc(inset: 0)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.94, green: 0.94, blue: 0.91), Color(red: 0.68, green: 0.69, blue: 0.67)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round)
                    )

                // Headband cushion (inner, slightly lighter)
                HeadbandArc(inset: s * 0.012)
                    .stroke(
                        Color(red: 0.82, green: 0.82, blue: 0.78).opacity(0.9),
                        style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round)
                    )

                // Yokes connecting band ends to the cups
                Capsule()
                    .fill(Color(red: 0.71, green: 0.72, blue: 0.69))
                    .frame(width: s * 0.035, height: s * 0.10)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -s * 0.315, y: s * 0.02)

                Capsule()
                    .fill(Color(red: 0.71, green: 0.72, blue: 0.69))
                    .frame(width: s * 0.035, height: s * 0.10)
                    .rotationEffect(.degrees(14))
                    .offset(x: s * 0.315, y: s * 0.02)

                earCup(size: s)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -s * 0.33, y: s * 0.175)

                earCup(size: s)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(7))
                    .offset(x: s * 0.33, y: s * 0.175)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1.05, contentMode: .fit)
    }

    private func earCup(size s: CGFloat) -> some View {
        ZStack {
            // Cup body
            RoundedRectangle(cornerRadius: s * 0.115)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.95, blue: 0.92), Color(red: 0.72, green: 0.73, blue: 0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.235, height: s * 0.335)
                .shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.012)

            // Soft top-edge sheen
            RoundedRectangle(cornerRadius: s * 0.115)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.65), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: s * 0.008
                )
                .frame(width: s * 0.235, height: s * 0.335)

            // Diagonal highlight
            Ellipse()
                .fill(.white.opacity(0.18))
                .frame(width: s * 0.10, height: s * 0.22)
                .rotationEffect(.degrees(18))
                .offset(x: -s * 0.045, y: -s * 0.05)
        }
    }
}

/// Top arc of the headband.
private struct HeadbandArc: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY + s * 0.16),
            radius: s * 0.335 - inset,
            startAngle: .degrees(197),
            endAngle: .degrees(343),
            clockwise: false
        )
        return path
    }
}
