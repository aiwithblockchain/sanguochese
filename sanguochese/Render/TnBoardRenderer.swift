//
//  TnBoardRenderer.swift
//  sanguochese
//
//  2 人标准中国象棋 · 棋盘渲染
//
//  用 SpriteKit 把标准 9×10 矩形棋盘 + 楚河汉界 + 九宫 + 棋子画出来。
//  渲染层只读棋盘状态，不修改规则层；每次 refreshPieces() 重建棋子节点。
//
//  节点层级（挂在 GameScene 上，整体平移到场景中心）：
//    boardRoot (SKNode)
//      ├─ gridLayer      网格线、九宫斜线、楚河汉界
//      ├─ highlightLayer 合法走法高亮
//      ├─ pieceLayer     棋子
//      └─ selectionLayer 选中棋子框
//
//  与 SgBoardRenderer 完全独立（标准矩形几何，非三瓣 120°）。
//

import SpriteKit

public final class TnBoardRenderer {

    public let mapper: TnCoordMapper

    /// 渲染根节点。GameScene 把它加为子节点并平移到场景中心。
    public let boardRoot = SKNode()

    private let gridLayer = SKNode()
    private let highlightLayer = SKNode()
    private let pieceLayer = SKNode()
    private let selectionLayer = SKNode()

    /// 红黑方主题色
    private let redColor = SKColor(red: 0.85, green: 0.20, blue: 0.15, alpha: 1.0)
    private let blackColor = SKColor(white: 0.12, alpha: 1.0)

    public init(cellSize: CGFloat, perspectiveColor: TnColor? = nil) {
        self.mapper = TnCoordMapper(cellSize: cellSize, perspectiveColor: perspectiveColor)
        boardRoot.addChild(gridLayer)
        boardRoot.addChild(highlightLayer)
        boardRoot.addChild(pieceLayer)
        boardRoot.addChild(selectionLayer)
        drawGrid()
    }

    // MARK: - 颜色辅助

    public func color(for color: TnColor) -> SKColor {
        color == .red ? redColor : blackColor
    }

    // MARK: - 棋盘网格

    /// 绘制 9×10 网格、九宫斜线、楚河汉界。只画一次。
    private func drawGrid() {
        let lineColor = SKColor(white: 0.30, alpha: 0.9)
        let lineWidth: CGFloat = 1.0
        let borderLineWidth: CGFloat = 2.5
        let borderColor = SKColor(white: 0.25, alpha: 1.0)
        let cs = mapper.cellSize

        // 横线（rank 0..9）。rank 4 与 rank 5 之间为河界，横线照画。
        for rank in 0...9 {
            let left = mapper.screenPos(for: TnPos(file: 0, rank: rank))
            let right = mapper.screenPos(for: TnPos(file: 8, rank: rank))
            let path = CGMutablePath()
            path.move(to: left)
            path.addLine(to: right)
            let node = SKShapeNode(path: path)
            let isBorder = (rank == 0 || rank == 9)
            node.lineWidth = isBorder ? borderLineWidth : lineWidth
            node.strokeColor = isBorder ? borderColor : lineColor
            node.isAntialiased = true
            gridLayer.addChild(node)
        }

        // 纵线（file 0..8）。
        // 河界处（rank 4 与 rank 5 之间）纵线断开：红方纵线画 rank 0..4，黑方画 rank 5..9。
        // 边线 file 0 和 file 8 贯通全盘。
        for file in 0...8 {
            if file == 0 || file == 8 {
                // 边线贯通
                let bottom = mapper.screenPos(for: TnPos(file: file, rank: 0))
                let top = mapper.screenPos(for: TnPos(file: file, rank: 9))
                let path = CGMutablePath()
                path.move(to: bottom)
                path.addLine(to: top)
                let node = SKShapeNode(path: path)
                node.lineWidth = borderLineWidth
                node.strokeColor = borderColor
                node.isAntialiased = true
                gridLayer.addChild(node)
            } else {
                // 红方半盘：rank 0..4
                let r0 = mapper.screenPos(for: TnPos(file: file, rank: 0))
                let r4 = mapper.screenPos(for: TnPos(file: file, rank: 4))
                let pathR = CGMutablePath()
                pathR.move(to: r0)
                pathR.addLine(to: r4)
                let nodeR = SKShapeNode(path: pathR)
                nodeR.lineWidth = lineWidth
                nodeR.strokeColor = lineColor
                nodeR.isAntialiased = true
                gridLayer.addChild(nodeR)
                // 黑方半盘：rank 5..9
                let r5 = mapper.screenPos(for: TnPos(file: file, rank: 5))
                let r9 = mapper.screenPos(for: TnPos(file: file, rank: 9))
                let pathB = CGMutablePath()
                pathB.move(to: r5)
                pathB.addLine(to: r9)
                let nodeB = SKShapeNode(path: pathB)
                nodeB.lineWidth = lineWidth
                nodeB.strokeColor = lineColor
                nodeB.isAntialiased = true
                gridLayer.addChild(nodeB)
            }
        }

        // 九宫斜线
        drawPalace(color: .red)
        drawPalace(color: .black)

        // 楚河汉界文字
        let riverY = (mapper.screenPos(for: TnPos(file: 0, rank: 4)).y
                      + mapper.screenPos(for: TnPos(file: 0, rank: 5)).y) / 2
        let riverLabel = SKLabelNode(text: "楚 河          漢 界")
        riverLabel.fontName = "PingFangSC-Semibold"
        riverLabel.fontSize = cs * 0.55
        riverLabel.fontColor = SKColor(white: 0.35, alpha: 0.8)
        riverLabel.position = CGPoint(x: 0, y: riverY)
        riverLabel.verticalAlignmentMode = .center
        riverLabel.zPosition = -0.5
        gridLayer.addChild(riverLabel)
    }

    /// 绘制某方九宫斜线（file 3..5，红 rank 0..2 / 黑 rank 7..9）
    private func drawPalace(color: TnColor) {
        let lineColor = SKColor(white: 0.30, alpha: 0.9)
        let lineWidth: CGFloat = 1.0
        let ranks: ClosedRange<Int> = color == .red ? (0...2) : (7...9)
        let p1 = mapper.screenPos(for: TnPos(file: 3, rank: ranks.lowerBound))
        let p2 = mapper.screenPos(for: TnPos(file: 5, rank: ranks.upperBound))
        let p3 = mapper.screenPos(for: TnPos(file: 5, rank: ranks.lowerBound))
        let p4 = mapper.screenPos(for: TnPos(file: 3, rank: ranks.upperBound))
        for (a, b) in [(p1, p2), (p3, p4)] {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let node = SKShapeNode(path: path)
            node.lineWidth = lineWidth
            node.strokeColor = lineColor
            node.isAntialiased = true
            gridLayer.addChild(node)
        }
    }

    // MARK: - 棋子

    /// 用给定棋盘状态刷新棋子层。
    public func refreshPieces(from board: TnBoard) {
        pieceLayer.removeAllChildren()
        for (pos, piece) in board.pieces {
            let node = makePieceNode(piece: piece, at: pos)
            pieceLayer.addChild(node)
        }
    }

    private func makePieceNode(piece: TnPiece, at pos: TnPos) -> SKNode {
        let center = mapper.screenPos(for: pos)
        let r = mapper.cellSize * 0.42
        let bg = SKShapeNode(circleOfRadius: r)
        bg.fillColor = SKColor(white: 0.97, alpha: 1.0)
        bg.strokeColor = color(for: piece.color)
        bg.lineWidth = 2.5
        bg.position = center
        bg.zPosition = 10

        let label = SKLabelNode(text: piece.displayChar)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = r * 1.1
        label.fontColor = color(for: piece.color)
        label.verticalAlignmentMode = .center
        label.zPosition = 11
        bg.addChild(label)
        label.position = .zero
        return bg
    }

    // MARK: - 高亮

    /// 高亮给定走法列表的目标格。
    public func highlightMoves(_ moves: [TnMove]) {
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
    public func select(_ pos: TnPos?) {
        selectionLayer.removeAllChildren()
        guard let pos = pos else { return }
        let cs = mapper.cellSize
        let center = mapper.screenPos(for: pos)
        let rect = CGRect(x: center.x - cs / 2, y: center.y - cs / 2, width: cs, height: cs)
        let frame = SKShapeNode(rect: rect)
        frame.fillColor = .clear
        frame.strokeColor = SKColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1.0)
        frame.lineWidth = 3.0
        frame.zPosition = 6
        selectionLayer.addChild(frame)
    }

    // MARK: - 走子动画

    /// 把 from 处的棋子节点移动到 to，完成后回调。
    /// 调用前应已 board.make(move)；此函数只负责视觉。
    public func animateMove(from: TnPos, to: TnPos, completion: @escaping () -> Void) {
        let fromPos = mapper.screenPos(for: from)
        let toPos = mapper.screenPos(for: to)
        guard let node = pieceLayer.children.first(where: { node in
            TnPointDistance(node.position, fromPos) < 1.0
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

private func TnPointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}
