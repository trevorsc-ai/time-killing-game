import SwiftUI

/// A scrapbook illustration: a char grid where each character is a palette id and `.` is transparent.
/// Files live in `Resources/Art/scrapbook/<id>.json`; the format is documented in docs/level-format.md.
struct ScrapbookArt: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var caption: String
    var width: Int
    var height: Int
    var rows: [String]
    /// Optional extra colors (single-character key -> "#RRGGBB") that add to or override the shared palette.
    var palette: [String: String]?
}

enum PixelArtLibrary {
    private static var cache: [String: ScrapbookArt] = [:]

    /// Loads `Art/scrapbook/<id>.json` through the content store (cached).
    static func load(id: String, content: ContentStore) -> ScrapbookArt? {
        if let hit = cache[id] { return hit }
        guard let data = content.artData(named: "scrapbook/\(id)"),
              let art = try? JSONDecoder().decode(ScrapbookArt.self, from: data) else { return nil }
        cache[id] = art
        return art
    }
}

/// Crisp nearest-neighbor rendering of a char-grid illustration. Cells are snapped to whole device pixels so
/// there is no blur or seams at any size.
struct PixelArtView: View {
    let art: ScrapbookArt
    /// Shared palette (`Art/palette.json`); per-art `palette` entries win.
    let palette: Palette
    /// Draw a flat single-color silhouette instead of the art (locked scrapbook items).
    var silhouette: Color?
    var highContrast: Bool = false

    @Environment(\.displayScale) private var displayScale

    private func buildColorMap() -> [Character: Color] {
        var map: [Character: Color] = [:]
        for c in palette.colors {
            if let ch = c.id.first { map[ch] = c.color(highContrast: highContrast) }
        }
        if let extra = art.palette {
            for (k, v) in extra {
                if let ch = k.first { map[ch] = Color(hex: v) }
            }
        }
        return map
    }

    var body: some View {
        let colors = buildColorMap()
        let rows: [[Character]] = art.rows.map { Array($0) }
        let cols = max(art.width, 1)
        let rowCount = max(rows.count, 1)
        let scale = max(displayScale, 1)
        let flat = silhouette
        return Canvas { context, size in
            let raw = min(size.width / CGFloat(cols), size.height / CGFloat(rowCount))
            let cell = floor(raw * scale) / scale
            guard cell > 0 else { return }
            let originX = (size.width - cell * CGFloat(cols)) / 2
            let originY = (size.height - cell * CGFloat(rowCount)) / 2
            let snapX = (originX * scale).rounded() / scale
            let snapY = (originY * scale).rounded() / scale
            for (r, line) in rows.enumerated() {
                var c = 0
                while c < line.count {
                    let ch = line[c]
                    var fill: Color? = nil
                    if ch != "." {
                        if let s = flat {
                            fill = colors[ch] != nil ? s : nil
                        } else {
                            fill = colors[ch]
                        }
                    }
                    guard let color = fill else { c += 1; continue }
                    var end = c + 1
                    while end < line.count && line[end] == ch { end += 1 }
                    let rect = CGRect(x: snapX + cell * CGFloat(c),
                                      y: snapY + cell * CGFloat(r),
                                      width: cell * CGFloat(end - c),
                                      height: cell)
                    context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                    c = end
                }
            }
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rowCount), contentMode: .fit)
        .accessibilityHidden(true)
    }
}
