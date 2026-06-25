//
//  TnGameScene.swift
//  sanguochese
//
//  2 人标准中国象棋 · 主场景
//
//  职责：
//    - 持有 TnBoard 规则状态与 TnBoardRenderer 渲染器
//    - 处理点击：选中棋子 / 高亮合法走法 / 执行走子
//    - 回合轮转 红→黑→红
//    - 顶部状态栏显示当前回合方
//    - AI 方自动走子（后台搜索 + 主线程落子）
//
//  与 GameScene 完全独立（Tn* 类型）。
//

import SpriteKit
import GameplayKit

class TnGameScene: SKScene {

    // MARK: - 规则与渲染

    private var board: TnBoard = TnLayout.initialBoard()
    private var renderer: TnBoardRenderer!

    // MARK: - AI 配置

    /// 人类操作的方。默认 [.red]（人机模式人类走红）。
    ///人人对战 = [.red, .black]。
    var humanColors: Set<TnColor> = [.red]
    /// AI 难度
    var aiDifficulty: TnDifficulty = .normal
    /// AI 是否正在思考（防止重入）
    private var aiThinking = false

    /// 棋盘视角：该方在屏幕下方。nil = 红方在下（默认）。
    var perspectiveColor: TnColor? = nil

    // MARK: - 交互状态

    private var selectedPos: TnPos?
    private var legalForSelected: [TnMove] = []

    // MARK: - UI 节点

    private var statusLabel: SKLabelNode!
    private var statusBg: SKShapeNode!
    private var boardRoot: SKNode { renderer.boardRoot }

    // MARK: - 生命周期

    override func didMove(to view: SKView) {
        self.backgroundColor = SKColor(white: 0.92, alpha: 1.0)
        self.scaleMode = .aspectFill

        // 根据场景尺寸自适应格子大小
        // 棋盘宽 8·cs，高 9·cs，留 15% 边距 + 顶部状态栏
        let side = min(self.size.width, self.size.height)
        let cs = side / (9.0 * 1.15)
        renderer = TnBoardRenderer(cellSize: cs, perspectiveColor: perspectiveColor)

        // 把棋盘根节点放到场景中心
        renderer.boardRoot.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
        addChild(renderer.boardRoot)

        // 状态栏
        let safeTop = view.safeAreaInsets.top
        let topOffset = max(safeTop + 12, 44)
        let statusY = self.size.height - topOffset

        statusBg = SKShapeNode(rectOf: CGSize(width: 160, height: 36), cornerRadius: 12)
        statusBg.fillColor = SKColor(white: 1.0, alpha: 0.85)
        statusBg.strokeColor = SKColor(white: 0.7, alpha: 0.5)
        statusBg.lineWidth = 1.0
        statusBg.position = CGPoint(x: self.size.width / 2, y: statusY)
        statusBg.zPosition = -1
        addChild(statusBg)

        statusLabel = SKLabelNode(text: "")
        statusLabel.fontName = "PingFangSC-Semibold"
        statusLabel.fontSize = 20
        statusLabel.fontColor = SKColor(white: 0.2, alpha: 1.0)
        statusLabel.position = CGPoint(x: self.size.width / 2, y: statusY)
        statusLabel.verticalAlignmentMode = .center
        addChild(statusLabel)

        renderer.refreshPieces(from: board)
        updateStatus()
        // 首回合若 AI 先走（人类未选红方），触发 AI
        triggerAIIfNeeded()
    }

    // MARK: - 状态栏

    private func updateStatus() {
        let side = board.sideToMove
        let isHuman = humanColors.contains(side)
        let prefix = isHuman ? "" : "[AI] "
        statusLabel.text = "\(prefix)\(side.displayName)方走子"
        let c = renderer.color(for: side)
        statusLabel.fontColor = c
        statusBg.strokeColor = c.withAlphaComponent(0.8)
    }

    // MARK: - 点击交互

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        // 转到以棋盘中心为原点的坐标系
        let local = CGPoint(x: location.x - boardRoot.position.x,
                            y: location.y - boardRoot.position.y)
        guard let pos = renderer.mapper.pos(at: local) else {
            cancelSelection()
            return
        }
        handleTap(at: pos)
    }

    private func handleTap(at pos: TnPos) {
        // AI 回合不响应人类点击
        if !humanColors.contains(board.sideToMove) { return }
        let piece = board.piece(at: pos)

        // 已选中棋子时
        if selectedPos != nil {
            // 点到合法走法目标 → 执行走子
            if let move = legalForSelected.first(where: { $0.to == pos }) {
                executeMove(move)
                return
            }
            // 点到己方另一枚棋子 → 切换选中
            if let p = piece, p.color == board.sideToMove {
                selectPiece(at: pos)
                return
            }
            // 其他情况 → 取消选中
            cancelSelection()
            return
        }

        // 未选中时：点到当前回合方的棋子 → 选中
        if let p = piece, p.color == board.sideToMove {
            selectPiece(at: pos)
        }
    }

    private func selectPiece(at pos: TnPos) {
        selectedPos = pos
        let allLegal = TnLegality.legalMoves(for: board.sideToMove, on: board)
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

    // MARK: - 走子执行

    private func executeMove(_ move: TnMove) {
        let from = move.from
        // 视觉动画先走（基于 apply 前的棋子位置）
        renderer.clearHighlights()
        renderer.select(nil)
        selectedPos = nil
        legalForSelected = []

        // 规则层 + 结算
        let outcome = TnGameFlow.play(move, on: board)

        renderer.animateMove(from: from, to: move.to) { [weak self] in
            guard let self = self else { return }
            self.renderer.refreshPieces(from: self.board)
            self.handleOutcome(outcome)
        }
    }

    // MARK: - AI 走子

    /// 若当前回合方是 AI，后台搜索并落子。
    private func triggerAIIfNeeded() {
        guard !aiThinking else { return }
        let side = board.sideToMove
        guard !humanColors.contains(side) else { return }
        guard case .ongoing = TnGameFlow.result(of: board) else { return }

        aiThinking = true
        updateStatus()

        // 拷贝棋盘在后台线程搜索，避免阻塞渲染。
        let searchBoard = TnBoard(copy: board)
        let difficulty = aiDifficulty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = TnSearch.chooseMove(for: side,
                                             on: searchBoard,
                                             difficulty: difficulty)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.aiThinking = false
                guard let move = result.move else { return }
                self.executeMove(move)
            }
        }
    }

    private func handleOutcome(_ outcome: TnMoveOutcome) {
        switch outcome {
        case .ongoing:
            updateStatus()
            triggerAIIfNeeded()
        case .kingCaptured(let winner):
            flashBanner("🏆 \(winner.displayName)方吃帅获胜！")
            statusLabel.text = "🏆 \(winner.displayName)方获胜"
            statusLabel.fontColor = renderer.color(for: winner)
        case .noMoves(let winner):
            flashBanner("🏆 \(winner.displayName)方将死对手！")
            statusLabel.text = "🏆 \(winner.displayName)方获胜"
            statusLabel.fontColor = renderer.color(for: winner)
        }
    }

    private func flashBanner(_ text: String) {
        let banner = SKLabelNode(text: text)
        banner.fontName = "PingFangSC-Semibold"
        banner.fontSize = 24
        banner.fontColor = SKColor(white: 0.15, alpha: 1.0)
        banner.position = CGPoint(x: self.size.width / 2, y: self.size.height - 70)
        banner.verticalAlignmentMode = .center
        banner.zPosition = 100
        banner.alpha = 0
        addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent()
        ]))
    }
}
