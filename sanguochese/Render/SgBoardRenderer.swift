//
//  SgBoardRenderer.swift
//  sanguochese
//
//  三国象棋 · 棋盘渲染 (P2-1 / P2-2 / P2-3)
//
//  用 SpriteKit 把三瓣地盘 + 九宫 + 国界 + 棋子画出来。
//  渲染层只读棋盘状态，不修改规则层；每次 refreshBoard() 重建可变节点。
//
//  节点层级（挂在 GameScene 上，整体平移到场景中心）：
//    boardRoot (SKNode)
//      ├─ gridLayer     地盘网格线、九宫斜线、国界边
//      ├─ highlightLayer 合法走法高亮
//      ├─ pieceLayer    棋子
//      └─ selectionLayer 选中棋子框
//

import SpriteKit

public final class SgBoardRenderer {

    public let mapper: SgCoordMapper

    /// 渲染根节点。GameScene 把它加为子节点并平移到场景中心。
    public let boardRoot = SKNode()

    private let gridLayer = SKNode()
    private let forkedLayer = SKNode()      // 动态虚线出国线（仅当前应走方）
    private let highlightLayer = SKNode()
    private let pieceLayer = SKNode()
    private let selectionLayer = SKNode()

    /// 三方主题色
    private let nationColor: [SgNation: SKColor] = [
        .wei: SKColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0),
        .shu: SKColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1.0),
        .wu:  SKColor(red: 0.20, green: 0.70, blue: 0.40, alpha: 1.0),
    ]

    /// 需要绘制地盘的国家集合（2 人模式只画两方，第三方瓣留空）。
    private let aliveNations: Set<SgNation>

    /// 棋盘布局（Y 形 / 矩形）
    private let layout: SgBoardLayout

    public init(cellSize: CGFloat, perspectiveNation: SgNation? = nil,
                aliveNations: Set<SgNation> = Set(SgNation.allCases),
                layout: SgBoardLayout = .yShape) {
        self.mapper = SgCoordMapper(cellSize: cellSize, perspectiveNation: perspectiveNation, layout: layout)
        self.aliveNations = aliveNations
        self.layout = layout
        boardRoot.addChild(gridLayer)
        boardRoot.addChild(forkedLayer)
        boardRoot.addChild(highlightLayer)
        boardRoot.addChild(pieceLayer)
        boardRoot.addChild(selectionLayer)
        drawGrid()
    }

    // MARK: - 颜色辅助

    public func color(for nation: SgNation) -> SKColor {
        return nationColor[nation] ?? .white
    }

    private func darkColor(for nation: SgNation) -> SKColor {
        let c = color(for: nation)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: 1.0)
    }

    // MARK: - P2-1 / P2-2 地盘与国界

    /// 绘制棋盘网格。只画一次。
    private func drawGrid() {
        switch layout {
        case .yShape:
            for nation in SgNation.allCases where aliveNations.contains(nation) {
                drawTerritory(for: nation)
            }
            drawCentralTriangle()
        case .rectangular(let bottom, let top):
            drawRectGrid(bottom: bottom, top: top)
        }
    }

    /// 绘制单方地盘：9×5 网格线 + 九宫斜线 + 国界边加粗。
    private func drawTerritory(for nation: SgNation) {
        let lineColor = SKColor(white: 0.35, alpha: 0.9)
        let lineWidth: CGFloat = 1.0
        let borderLineWidth: CGFloat = 2.5
        let borderColor = darkColor(for: nation)

        // 横线（rank 1..5）
        for rank in 1...5 {
            let left = mapper.screenPos(for: SgPos(nation: nation, file: 1, rank: rank))
            let right = mapper.screenPos(for: SgPos(nation: nation, file: 9, rank: rank))
            let path = CGMutablePath()
            path.move(to: left)
            path.addLine(to: right)
            let isBorder = (rank == 5)
            let node = SKShapeNode(path: path)
            node.lineWidth = isBorder ? borderLineWidth : lineWidth
            node.strokeColor = isBorder ? borderColor : lineColor
            node.glowWidth = 0
            node.isAntialiased = true
            gridLayer.addChild(node)
        }

        // 纵线（file 1..9）。在传统象棋中，河界一侧纵线只画到本方半盘；
        // 这里 file 1..9 都画到国界（rank 5），因为分叉在国界处发生。
        for file in 1...9 {
            let bottom = mapper.screenPos(for: SgPos(nation: nation, file: file, rank: 1))
            let top = mapper.screenPos(for: SgPos(nation: nation, file: file, rank: 5))
            let path = CGMutablePath()
            path.move(to: bottom)
            path.addLine(to: top)
            let node = SKShapeNode(path: path)
            node.lineWidth = lineWidth
            node.strokeColor = lineColor
            node.isAntialiased = true
            gridLayer.addChild(node)
        }

        // 九宫斜线（file 4..6, rank 1..3）
        let p1 = mapper.screenPos(for: SgPos(nation: nation, file: 4, rank: 1))
        let p2 = mapper.screenPos(for: SgPos(nation: nation, file: 6, rank: 3))
        let p3 = mapper.screenPos(for: SgPos(nation: nation, file: 6, rank: 1))
        let p4 = mapper.screenPos(for: SgPos(nation: nation, file: 4, rank: 3))
        for (a, b) in [(p1, p2), (p3, p4)] {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let node = SKShapeNode(path: path)
            node.lineWidth = lineWidth
            node.strokeColor = lineColor
            gridLayer.addChild(node)
        }

        // 国名标签：放在底线外侧
        let labelPos = mapper.screenPos(for: SgPos(nation: nation, file: 5, rank: 1))
        let out = outward(nation)
        let label = SKLabelNode(text: nation.displayName)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = 28
        label.fontColor = color(for: nation)
        label.position = CGPoint(x: labelPos.x + out.dx * 28, y: labelPos.y + out.dy * 28)
        label.verticalAlignmentMode = .center
        gridLayer.addChild(label)
    }

    /// 绘制中央由三条国界边拼成的等边三角形轮廓，强调"中央交汇"。
    private func drawCentralTriangle() {
        let path = CGMutablePath()
        let corners: [SgNation] = [.wei, .shu, .wu]
        let pts = corners.map { nation in
            // 国界边的端点 = file 1 rank 5 与 file 9 rank 5 的中点偏角点
            // 用国界边两端点之一作为三角形顶点：取 file 1 rank 5
            mapper.screenPos(for: SgPos(nation: nation, file: 1, rank: 5))
        }
        // 三条国界边各 9 格，相邻两方国界边的端点在中央交汇处相接。
        // 这里用每方 file 1 rank 5 与 file 9 rank 5 两端连成三角形的三条边。
        // 实际上三条国界边本身已由 drawTerritory 的 rank==5 横线画出，
        // 此处补画一个浅色填充三角形作为"中央交汇区"视觉提示。
        let v0 = mapper.screenPos(for: SgPos(nation: .wei, file: 1, rank: 5))
        let v1 = mapper.screenPos(for: SgPos(nation: .shu, file: 1, rank: 5))
        let v2 = mapper.screenPos(for: SgPos(nation: .wu,  file: 1, rank: 5))
        path.move(to: v0)
        path.addLine(to: v1)
        path.addLine(to: v2)
        path.closeSubpath()
        let tri = SKShapeNode(path: path)
        tri.fillColor = SKColor(white: 0.95, alpha: 0.5)
        tri.strokeColor = SKColor(white: 0.6, alpha: 0.6)
        tri.lineWidth = 1.0
        tri.zPosition = -1
        gridLayer.addChild(tri)
        _ = pts
    }

    // MARK: - 矩形棋盘（2 人模式）

    /// 绘制 9×10 矩形棋盘：纵线、横线、九宫斜线、河界文字、国名标签。
    private func drawRectGrid(bottom: SgNation, top: SgNation) {
        let lineColor = SKColor(white: 0.35, alpha: 0.9)
        let lineWidth: CGFloat = 1.0
        let borderLineWidth: CGFloat = 2.5
        let cs = mapper.cellSize

        // 纵线：9 条 column 0..8，从 row 0 到 row 9 连续（标准象棋纵线过河）
        for column in 0...8 {
            let bottomPos = screenPosRect(column: column, row: 0, bottom: bottom, top: top)
            let topPos = screenPosRect(column: column, row: 9, bottom: bottom, top: top)
            let path = CGMutablePath()
            path.move(to: bottomPos)
            path.addLine(to: topPos)
            let node = SKShapeNode(path: path)
            node.lineWidth = lineWidth
            node.strokeColor = lineColor
            node.isAntialiased = true
            gridLayer.addChild(node)
        }

        // 横线：底方 row 0..4 + 顶方 row 5..9（跳过河界 row 4↔5）
        for row in 0...9 {
            // 河界处不画横线（row 4 与 row 5 之间是河，不画这两条之间的连线）
            // 但 row 4 和 row 9 各画一条横线
            let leftPos = screenPosRect(column: 0, row: row, bottom: bottom, top: top)
            let rightPos = screenPosRect(column: 8, row: row, bottom: bottom, top: top)
            let path = CGMutablePath()
            path.move(to: leftPos)
            path.addLine(to: rightPos)
            let isBorder = (row == 0 || row == 9)
            let node = SKShapeNode(path: path)
            node.lineWidth = isBorder ? borderLineWidth : lineWidth
            // 底方用 bottom 色，顶方用 top 色，河界两侧用中性色
            let borderColor: SKColor
            if row <= 4 {
                borderColor = darkColor(for: bottom)
            } else {
                borderColor = darkColor(for: top)
            }
            node.strokeColor = isBorder ? borderColor : lineColor
            node.isAntialiased = true
            gridLayer.addChild(node)
        }

        // 九宫斜线：底方 column 3..5 × row 0..2；顶方 column 3..5 × row 7..9
        drawRectPalace(originColumn: 3, originRow: 0, bottom: bottom, top: top, color: lineColor, width: lineWidth)
        drawRectPalace(originColumn: 3, originRow: 7, bottom: bottom, top: top, color: lineColor, width: lineWidth)

        // 河界文字："楚河　汉界"
        let riverY = (screenPosRect(column: 0, row: 4, bottom: bottom, top: top).y
                     + screenPosRect(column: 0, row: 5, bottom: bottom, top: top).y) / 2.0
        let leftLabel = SKLabelNode(text: "楚 河")
        leftLabel.fontName = "PingFangSC-Semibold"
        leftLabel.fontSize = cs * 0.7
        leftLabel.fontColor = SKColor(white: 0.4, alpha: 0.8)
        leftLabel.position = CGPoint(x: -2.0 * cs, y: riverY)
        leftLabel.verticalAlignmentMode = .center
        leftLabel.zPosition = -0.5
        gridLayer.addChild(leftLabel)
        let rightLabel = SKLabelNode(text: "汉 界")
        rightLabel.fontName = "PingFangSC-Semibold"
        rightLabel.fontSize = cs * 0.7
        rightLabel.fontColor = SKColor(white: 0.4, alpha: 0.8)
        rightLabel.position = CGPoint(x: 2.0 * cs, y: riverY)
        rightLabel.verticalAlignmentMode = .center
        rightLabel.zPosition = -0.5
        gridLayer.addChild(rightLabel)

        // 国名标签：底方在 row 0 下方；顶方在 row 9 上方
        let bottomLabelPos = screenPosRect(column: 4, row: 0, bottom: bottom, top: top)
        let bottomLabel = SKLabelNode(text: bottom.displayName)
        bottomLabel.fontName = "PingFangSC-Semibold"
        bottomLabel.fontSize = 24
        bottomLabel.fontColor = color(for: bottom)
        bottomLabel.position = CGPoint(x: bottomLabelPos.x, y: bottomLabelPos.y - cs * 0.9)
        bottomLabel.verticalAlignmentMode = .center
        gridLayer.addChild(bottomLabel)

        let topLabelPos = screenPosRect(column: 4, row: 9, bottom: bottom, top: top)
        let topLabel = SKLabelNode(text: top.displayName)
        topLabel.fontName = "PingFangSC-Semibold"
        topLabel.fontSize = 24
        topLabel.fontColor = color(for: top)
        topLabel.position = CGPoint(x: topLabelPos.x, y: topLabelPos.y + cs * 0.9)
        topLabel.verticalAlignmentMode = .center
        gridLayer.addChild(topLabel)
    }

    /// 绘制矩形九宫斜线（2×2 范围，column origin..origin+2, row origin..origin+2）
    private func drawRectPalace(originColumn: Int, originRow: Int,
                                bottom: SgNation, top: SgNation,
                                color: SKColor, width: CGFloat) {
        // 九宫四角：左下、右下、右上、左上
        let lb = screenPosRect(column: originColumn, row: originRow, bottom: bottom, top: top)
        let rb = screenPosRect(column: originColumn + 2, row: originRow, bottom: bottom, top: top)
        let rt = screenPosRect(column: originColumn + 2, row: originRow + 2, bottom: bottom, top: top)
        let lt = screenPosRect(column: originColumn, row: originRow + 2, bottom: bottom, top: top)
        for (a, b) in [(lb, rt), (rb, lt)] {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let node = SKShapeNode(path: path)
            node.lineWidth = width
            node.strokeColor = color
            node.isAntialiased = true
            gridLayer.addChild(node)
        }
    }

    /// 矩形布局下 (column, row) → 屏幕坐标（与 SgCoordMapper.screenPos 矩形分支一致）
    private func screenPosRect(column: Int, row: Int, bottom: SgNation, top: SgNation) -> CGPoint {
        let cs = mapper.cellSize
        let x = CGFloat(column - 4) * cs
        let y = CGFloat(row - 4) * cs - 0.5 * cs
        return CGPoint(x: x, y: y)
    }

    private func outward(_ nation: SgNation) -> CGVector {
        let a = mapper.outwardAngle(of: nation)
        return CGVector(dx: cos(a), dy: sin(a))
    }

    /// 动态更新出国虚线：只绘制当前应走方一侧的 9 条分叉线，
    /// 避免三方交叉的混乱感。
    public func refreshForkedLines(for side: SgNation) {
        forkedLayer.removeAllChildren()
        // 矩形布局无国界分叉，不画虚线
        if case .rectangular = layout { return }

        let dashColor = color(for: side).withAlphaComponent(0.35)
        let dashWidth: CGFloat = 0.8
        let dashLength: CGFloat = 5.0
        let gapLength: CGFloat = 4.0

        for file in 1...9 {
            let start = mapper.screenPos(for: SgPos(nation: side, file: file, rank: 5))
            for enemy in side.opponents() where aliveNations.contains(enemy) {
                let end = mapper.screenPos(for: SgPos(nation: enemy, file: 10 - file, rank: 5))
                drawDashedLine(from: start, to: end,
                               color: dashColor, width: dashWidth,
                               dash: dashLength, gap: gapLength,
                               to: forkedLayer)
            }
        }
    }

    private func drawDashedLine(from: CGPoint, to: CGPoint,
                                color: SKColor, width: CGFloat,
                                dash: CGFloat, gap: CGFloat,
                                to layer: SKNode) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0 else { return }
        let ux = dx / dist
        let uy = dy / dist

        var pos: CGFloat = 0
        var drawing = true
        while pos < dist {
            let seg = drawing ? min(dash, dist - pos) : min(gap, dist - pos)
            if drawing {
                let a = CGPoint(x: from.x + ux * pos, y: from.y + uy * pos)
                let b = CGPoint(x: from.x + ux * (pos + seg), y: from.y + uy * (pos + seg))
                let path = CGMutablePath()
                path.move(to: a)
                path.addLine(to: b)
                let node = SKShapeNode(path: path)
                node.strokeColor = color
                node.lineWidth = width
                node.isAntialiased = true
                node.zPosition = -0.5
                layer.addChild(node)
            }
            pos += seg
            drawing.toggle()
        }
    }

    // MARK: - P2-3 棋子

    /// 用给定棋盘状态刷新棋子层。
    public func refreshPieces(from board: SgBoard) {
        pieceLayer.removeAllChildren()
        for (pos, piece) in board.pieces {
            let node = makePieceNode(piece: piece, at: pos)
            pieceLayer.addChild(node)
        }
    }

    private func makePieceNode(piece: SgPiece, at pos: SgPos) -> SKNode {
        let center = mapper.screenPos(for: pos)
        let r = mapper.cellSize * 0.42
        let bg = SKShapeNode(circleOfRadius: r)
        bg.fillColor = SKColor(white: 0.98, alpha: 1.0)
        bg.strokeColor = color(for: piece.nation)
        bg.lineWidth = 2.5
        bg.position = center
        bg.zPosition = 10

        let label = SKLabelNode(text: piece.type.displayName)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = r * 1.1
        label.fontColor = color(for: piece.nation)
        label.position = center
        label.verticalAlignmentMode = .center
        label.zPosition = 11
        // 把标签作为 bg 的子节点更便于动画，但 SKLabelNode 与 SKShapeNode 同级也可
        bg.addChild(label)
        label.position = .zero
        return bg
    }

    // MARK: - 高亮（P3-2 合法走法）

    /// 高亮给定走法列表的目标格。
    public func highlightMoves(_ moves: [SgMove]) {
        highlightLayer.removeAllChildren()
        for m in moves {
            let center = mapper.screenPos(for: m.to)
            let r = mapper.cellSize * 0.30
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = SKColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 0.85)
            dot.strokeColor = .clear
            dot.position = center
            dot.zPosition = 5
            highlightLayer.addChild(dot)
        }
    }

    public func clearHighlights() {
        highlightLayer.removeAllChildren()
    }

    /// 选中棋子框
    public func select(_ pos: SgPos?) {
        selectionLayer.removeAllChildren()
        guard let pos = pos else { return }
        let path = mapper.cellPath(for: pos)
        let frame = SKShapeNode(path: path)
        frame.fillColor = .clear
        frame.strokeColor = SKColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1.0)
        frame.lineWidth = 3.0
        frame.zPosition = 6
        selectionLayer.addChild(frame)
    }

    // MARK: - 走子动画（P3-3）

    /// 把 from 处的棋子节点移动到 to，完成后回调。
    /// 调用前应已 board.apply(move)；此函数只负责视觉。
    public func animateMove(from: SgPos, to: SgPos, completion: @escaping () -> Void) {
        let fromPos = mapper.screenPos(for: from)
        let toPos = mapper.screenPos(for: to)
        // 找到 from 处的棋子节点
        guard let node = pieceLayer.children.first(where: { node in
            SKPointDistance(node.position, fromPos) < 1.0
        }) else {
            completion()
            return
        }
        let move = SKAction.move(to: toPos, duration: 0.25)
        move.timingMode = .easeInEaseOut
        node.run(move) {
            completion()
        }
    }
}

private func SKPointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}
