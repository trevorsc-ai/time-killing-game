import CoreGraphics

/// Geometry of the Pixel Picnic board, shared by the SpriteKit scene and the SwiftUI accessibility overlay.
/// All rectangles use top-left-origin ("UIKit") coordinates inside `size`.
struct PixelLayout: Equatable {
    var size: CGSize
    var columns: Int
    var rows: Int
    var slotCount: Int
    var laneCount: Int

    // Derived
    var canvasRect: CGRect = .zero
    var gridRect: CGRect = .zero
    var cell: CGFloat = 0
    var trayRect: CGRect = .zero
    var slotSize: CGFloat = 0
    var slotRects: [CGRect] = []
    var laneFrontSize: CGFloat = 0
    var laneQueueScale: CGFloat = 0.62
    var laneFrontRects: [CGRect] = []
    /// Centers (top-left origin) for queue positions 1...maxQueue per lane.
    var laneQueueCenters: [[CGPoint]] = []
    var laneHitRects: [CGRect] = []

    static let maxQueueShown = 2

    init(size: CGSize, columns: Int, rows: Int, slotCount: Int, laneCount: Int) {
        self.size = size
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.slotCount = max(1, slotCount)
        self.laneCount = max(1, laneCount)
        compute(compact: false)
        // Big pictures on small phones: trade tray/lane size for picture size so blocks stay readable.
        if cell < Self.comfortableCell {
            let normal = self
            compute(compact: true)
            if cell <= normal.cell { self = normal }
        }
    }

    /// Smallest block size (points) that still reads comfortably.
    static let comfortableCell: CGFloat = 14

    /// True when the fit-to-screen picture is below the comfortable block size (the board then offers a zoom toggle).
    var isCramped: Bool { cell < Self.comfortableCell }

    /// A scene height tall enough for a comfortable block size (used by the zoomed, scrollable board).
    static func tallHeight(width: CGFloat, base: CGFloat, columns: Int, rows: Int, slotCount: Int, laneCount: Int) -> CGFloat {
        let target = min(20, floor((width - 28) / CGFloat(max(columns, 1))))
        var h = base
        while h < base * 3 {
            let l = PixelLayout(size: CGSize(width: width, height: h), columns: columns, rows: rows, slotCount: slotCount, laneCount: laneCount)
            if l.cell >= target { return h }
            h += 24
        }
        return base * 3
    }

    private mutating func compute(compact: Bool) {
        let W = max(size.width, 120)
        let H = max(size.height, 200)
        let margin: CGFloat = compact ? 6 : 10
        let gap: CGFloat = compact ? 6 : 10

        // Tray
        let slotSide = min(max((W - 2 * margin - 16) / CGFloat(slotCount) - 8, 40), compact ? 48 : 64)
        slotSize = slotSide
        let trayH = slotSide + 14
        let trayW = CGFloat(slotCount) * (slotSide + 8) + 8
        // Lanes
        let laneW = (W - 2 * margin) / CGFloat(laneCount)
        let front = min(max(laneW - 20, 44), compact ? 56 : 80)
        laneFrontSize = front
        let qs = front * laneQueueScale
        let queueStep = qs * 0.5
        let lanesH = front + qs * (0.65 + 0.5 * CGFloat(Self.maxQueueShown - 1)) + 8

        // Grid gets whatever is left.
        let availH = H - trayH - lanesH - 2 * gap - 2 * margin
        let availW = W - 2 * margin - 8
        let c = floor(min(availW / CGFloat(columns), availH / CGFloat(rows)))
        cell = max(min(c, 44), 6)
        let gw = cell * CGFloat(columns)
        let gh = cell * CGFloat(rows)
        let gridTop = margin + max(0, (availH - gh) / 2)
        gridRect = CGRect(x: (W - gw) / 2, y: gridTop, width: gw, height: gh)
        canvasRect = gridRect.insetBy(dx: -6, dy: -6)

        // Tray directly below the grid area.
        let trayTop = margin + availH + gap
        trayRect = CGRect(x: (W - trayW) / 2, y: trayTop, width: trayW, height: trayH)
        slotRects = (0..<slotCount).map { i in
            CGRect(x: trayRect.minX + 8 + CGFloat(i) * (slotSide + 8), y: trayRect.minY + 7, width: slotSide, height: slotSide)
        }

        // Lanes below the tray.
        let lanesTop = trayTop + trayH + gap
        laneFrontRects = []
        laneQueueCenters = []
        laneHitRects = []
        for l in 0..<laneCount {
            let cx = margin + laneW * (CGFloat(l) + 0.5)
            let r = CGRect(x: cx - front / 2, y: lanesTop, width: front, height: front)
            laneFrontRects.append(r)
            var centers: [CGPoint] = []
            for q in 1...Self.maxQueueShown {
                centers.append(CGPoint(x: cx, y: r.maxY + qs * 0.15 + queueStep * CGFloat(q - 1)))
            }
            laneQueueCenters.append(centers)
            laneHitRects.append(CGRect(x: cx - laneW / 2, y: lanesTop - 4, width: laneW, height: front + 8))
        }
    }

    func cellRect(_ idx: Int) -> CGRect {
        let r = idx / columns
        let c = idx - r * columns
        return CGRect(x: gridRect.minX + CGFloat(c) * cell, y: gridRect.minY + CGFloat(r) * cell, width: cell, height: cell)
    }
}
