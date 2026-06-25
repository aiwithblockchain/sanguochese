//
//  GameScene.swift
//  sanguochese
//
//  三国象棋 · 主场景 (P2 棋盘渲染 + P3 人人对战)
//
//  职责：
//    - 持有 SgBoard 规则状态与 SgBoardRenderer 渲染器
//    - 处理点击：选中棋子 / 高亮合法走法 / 执行走子
//    - 回合轮转 魏→蜀→吴
//    - 顶部状态栏显示当前回合方
//
//  本阶段不含灭国吞并结算（P4），仅跑通走子循环。
//

import SpriteKit
import GameplayKit

class GameScene: SKScene {

    // MARK: - 规则与渲染

    private var board: SgBoard = SgLayout.initialBoard()
    private var renderer: SgBoardRenderer!

    // MARK: - 交互状态

    private var selectedPos: SgPos?
    private var legalForSelected: [SgMove] = []

    // MARK: - UI 节点

    private var statusLabel: SKLabelNode!
    private var boardRoot: SKNode { renderer.boardRoot }

    // MARK: - 生命周期

    override func didMove(to view: SKView) {
        self.backgroundColor = SKColor(white: 0.92, alpha: 1.0)
        self.scaleMode = .aspectFill

        // 根据场景尺寸自适应格子大小
        let side = min(self.size.width, self.size.height)
        // 棋盘直径 ≈ 2·boardRadius，留 15% 边距 + 顶部状态栏空间
        let cellSize = side / (2.0 * (9.0 * CGFloat(3).squareRoot() / 6.0 + 4.0) * 1.15)
        renderer = SgBoardRenderer(cellSize: cellSize)

        // 把棋盘根节点放到场景中心
        renderer.boardRoot.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
        addChild(renderer.boardRoot)

        // 状态栏
        statusLabel = SKLabelNode(text: "")
        statusLabel.fontName = "PingFangSC-Semibold"
        statusLabel.fontSize = 22
        statusLabel.fontColor = SKColor(white: 0.2, alpha: 1.0)
        statusLabel.position = CGPoint(x: self.size.width / 2, y: self.size.height - 40)
        statusLabel.verticalAlignmentMode = .center
        addChild(statusLabel)

        renderer.refreshPieces(from: board)
        updateStatus()
    }

    // MARK: - 状态栏

    private func updateStatus() {
        let side = board.sideToMove
        statusLabel.text = "\(side.displayName)方走子"
        statusLabel.fontColor = renderer.color(for: side)
    }

    // MARK: - 点击交互 (P3-1 / P3-2 / P3-5)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        // 转到以棋盘中心为原点的坐标系
        let local = CGPoint(x: location.x - boardRoot.position.x,
                            y: location.y - boardRoot.position.y)
        guard let pos = renderer.mapper.pos(at: local) else {
            // 点到棋盘外：取消选中
            cancelSelection()
            return
        }
        handleTap(at: pos)
    }

    private func handleTap(at pos: SgPos) {
        let piece = board.piece(at: pos)

        // 已选中棋子时
        if let from = selectedPos {
            // 点到合法走法目标 → 执行走子
            if let move = legalForSelected.first(where: { $0.to == pos }) {
                executeMove(move)
                return
            }
            // 点到己方另一枚棋子 → 切换选中
            if let p = piece, p.nation == board.sideToMove {
                selectPiece(at: pos)
                return
            }
            // 其他情况 → 取消选中
            cancelSelection()
            return
        }

        // 未选中时：点到当前回合方的棋子 → 选中
        if let p = piece, p.nation == board.sideToMove {
            selectPiece(at: pos)
        }
    }

    private func selectPiece(at pos: SgPos) {
        selectedPos = pos
        // 生成该棋子的合法走法（过滤主帅互照）
        let allLegal = SgLegality.legalMoves(for: board.sideToMove, on: board)
        legalForSelected = allLegal.filter { $0.from == pos }
        renderer.select(pos)
        renderer.highlightMoves(legalForSelected)
    }

    private func cancelSelection() {
        selectedPos = nil
        legalForSelected = []
        renderer.select(nil)
        renderer.clearHighlights()
    }

    // MARK: - 走子执行 (P3-3 / P3-4)

    private func executeMove(_ move: SgMove) {
        let from = move.from
        // 规则层执行
        let captured = board.apply(move)
        // 视觉动画
        renderer.clearHighlights()
        renderer.select(nil)
        selectedPos = nil
        legalForSelected = []

        renderer.animateMove(from: from, to: move.to) { [weak self] in
            guard let self = self else { return }
            // 动画结束后重建棋子层（吃子需移除被吃节点）
            self.renderer.refreshPieces(from: self.board)
            // 回合轮转
            self.advanceTurn()
        }
    }

    private func advanceTurn() {
        // P3 阶段：简单的回合轮转。灭国判定留给 P4。
        board.sideToMove = board.sideToMove.next()
        // 跳过已灭国方（P4 之前不会发生，但保持健壮）
        while !board.isAlive(board.sideToMove) {
            board.sideToMove = board.sideToMove.next()
        }
        updateStatus()
    }
}
