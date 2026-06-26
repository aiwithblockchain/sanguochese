//
//  GameScene.swift
//  sanguochese
//
//  三国象棋 · 主场景 (P2 棋盘渲染 + P3 人人对战 + P5 人机对战 + P6 AI 解说)
//
//  职责：
//    - 持有 SgBoard 规则状态与 SgBoardRenderer 渲染器
//    - 处理点击：选中棋子 / 高亮合法走法 / 执行走子
//    - 回合轮转 魏→蜀→吴
//    - 顶部状态栏显示当前回合方
//    - P5：AI 方自动走子（后台搜索 + 主线程落子）
//    - P6：每步走子后异步生成角色化解说，底部气泡展示
//

import SpriteKit
import GameplayKit
import SgEngine

class GameScene: SKScene {

    // MARK: - 规则与渲染

    private var board: SgBoard = SgLayout.initialBoard()
    private var renderer: SgBoardRenderer!

    // MARK: - AI 配置 (P5)

    /// 玩家阵营：这些方由人类操作。其余存活方由 AI 接管。
    /// 默认空集合 = 人人对战（P3 模式）。
    var humanSides: Set<SgNation> = []
    /// AI 难度
    var aiDifficulty: SgDifficulty = .normal
    /// 对局模式（三方 / 两方）。默认三方。
    /// 必须在 presentScene 前由 GameViewController 注入。
    var gameMode: SgGameMode = .threeNation
    /// AI 是否正在思考（防止重入）
    private var aiThinking = false

    // MARK: - 解说配置 (P6)

    /// DeepSeek 解说桥接（nil = 不启用解说）
    var commentaryBridge: SgDeepSeekBridge?
    /// 玩家阵营（用于选择解说者）；人人对战时取魏方视角
    var commentarySide: SgNation = .shu

    /// 棋盘视角阵营：该方地盘朝向屏幕下方展开。
    /// nil = 默认（魏方在上）。由 GameViewController 注入。
    var perspectiveSide: SgNation? = nil

    // MARK: - 交互状态

    private var selectedPos: SgPos?
    private var legalForSelected: [SgMove] = []

    // MARK: - UI 节点

    private var statusLabel: SKLabelNode!
    private var statusBg: SKShapeNode!
    private var commentaryLabel: SKLabelNode?
    private var boardRoot: SKNode { renderer.boardRoot }

    // MARK: - 生命周期

    override func didMove(to view: SKView) {
        self.backgroundColor = SKColor(white: 0.92, alpha: 1.0)
        self.scaleMode = .aspectFill

        // 按模式初始化棋盘
        switch gameMode {
        case .threeNation:
            board = SgLayout.initialBoard()
        case .twoNation(let human, let ai):
            board = SgLayout.initialBoard(human: human, ai: ai)
        }

        // 根据场景尺寸自适应格子大小
        let side = min(self.size.width, self.size.height)
        let cellSize: CGFloat
        let layout: SgBoardLayout
        switch gameMode {
        case .threeNation:
            // 棋盘直径 ≈ 2·boardRadius，留 15% 边距 + 顶部状态栏空间
            cellSize = side / (2.0 * (9.0 * CGFloat(3).squareRoot() / 6.0 + 4.0) * 1.15)
            layout = .yShape
        case .twoNation(let human, let ai):
            // 矩形 9×10：宽 9 格 + 边距，高 10 格 + 顶部状态栏 + 边距
            cellSize = min(self.size.width / 9.5, self.size.height / 11.0)
            let bottom = perspectiveSide ?? human
            layout = .rectangular(bottom: bottom, top: ai)
        }
        renderer = SgBoardRenderer(cellSize: cellSize,
                                   perspectiveNation: perspectiveSide,
                                   aliveNations: board.aliveNations,
                                   layout: layout)

        // 把棋盘根节点放到场景中心
        renderer.boardRoot.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
        addChild(renderer.boardRoot)

        // 状态栏（避开灵动岛 / 刘海）
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

        // 解说气泡（底部）
        if commentaryBridge != nil {
            let label = SKLabelNode(text: "")
            label.fontName = "PingFangSC-Regular"
            label.fontSize = 16
            label.fontColor = SKColor(white: 0.25, alpha: 1.0)
            label.position = CGPoint(x: self.size.width / 2, y: 36)
            label.verticalAlignmentMode = .center
            label.zPosition = 100
            label.numberOfLines = 0
            addChild(label)
            commentaryLabel = label
        }

        renderer.refreshPieces(from: board)
        renderer.refreshForkedLines(for: board.sideToMove)
        updateStatus()
        // 首回合若 AI 先走（玩家未选魏方），触发 AI
        triggerAIIfNeeded()
    }

    // MARK: - 状态栏

    private func updateStatus() {
        let side = board.sideToMove
        let isHuman = humanSides.contains(side)
        let prefix = isHuman ? "" : "[AI] "
        statusLabel.text = "\(prefix)\(side.displayName)方走子"
        let c = renderer.color(for: side)
        statusLabel.fontColor = c
        statusBg.strokeColor = c.withAlphaComponent(0.8)
        renderer.refreshForkedLines(for: side)
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
        // AI 回合不响应人类点击
        if !humanSides.contains(board.sideToMove) { return }
        let piece = board.piece(at: pos)

        // 已选中棋子时
        if selectedPos != nil {
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

    // MARK: - 走子执行 (P3-3 / P3-4 / P4 结算)

    private func executeMove(_ move: SgMove) {
        let from = move.from
        // 走子方必须在 play 之前记录（play 后 sideToMove 已轮转）
        let mover = board.sideToMove
        // 视觉动画先走（基于 apply 前的棋子位置）
        renderer.clearHighlights()
        renderer.select(nil)
        selectedPos = nil
        legalForSelected = []

        // 规则层 + 结算（含吞并/清空/终局）
        let outcome = SgGameFlow.play(move, on: board)

        // P6：异步生成解说（不阻塞动画）
        requestCommentary(for: move, mover: mover)

        renderer.animateMove(from: from, to: move.to) { [weak self] in
            guard let self = self else { return }
            self.renderer.refreshPieces(from: self.board)
            self.handleOutcome(outcome)
        }
    }

    /// P6：请求解说（异步）
    private func requestCommentary(for move: SgMove, mover: SgNation) {
        guard let bridge = commentaryBridge, let label = commentaryLabel else { return }
        let situation = SgBoardDescriber.describe(board: board, lastMove: move)
        let moveText = "刚走：\(mover.displayName)方 \(move.description)"
        let isPlayer = humanSides.contains(mover)
        // 解说者：玩家方用谋士视角，AI 方用其君主视角
        let role: SgRole
        if isPlayer {
            role = SgRole.commentator(for: commentarySide)
        } else {
            role = SgRole.monarch(of: mover)
        }
        let prompt = SgRolePrompt.build(role: role,
                                        situation: situation,
                                        moveText: moveText,
                                        isPlayerMove: isPlayer)
        label.text = "「\(role.displayName)沉思中…」"
        label.alpha = 1.0
        bridge.commentate(prompt: prompt, role: role) { [weak self] text in
            guard self != nil else { return }
            label.text = "「\(text)」"
            label.alpha = 0
            label.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.3),
                SKAction.wait(forDuration: 4.0),
                SKAction.fadeOut(withDuration: 0.6)
            ]))
        }
    }

    // MARK: - AI 走子 (P5-6)

    /// 若当前回合方是 AI，后台搜索并落子。
    private func triggerAIIfNeeded() {
        guard !aiThinking else { return }
        let side = board.sideToMove
        guard !humanSides.contains(side) else { return }
        guard case .ongoing = SgGameFlow.result(of: board) else { return }

        aiThinking = true
        updateStatus()

        // 拷贝棋盘在后台线程搜索，避免阻塞渲染。
        let searchBoard = SgBoard(copy: board)
        let difficulty = aiDifficulty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SgSearch.chooseMove(for: side,
                                             on: searchBoard,
                                             difficulty: difficulty)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.aiThinking = false
                guard let move = result.move else { return }
                // 确保局面未被人类在等待期间改动（AI 回合人类无法点击，简单信任）
                self.executeMove(move)
            }
        }
    }

    private func handleOutcome(_ outcome: SgMoveOutcome) {
        switch outcome {
        case .ongoing:
            updateStatus()
            triggerAIIfNeeded()
        case .annexed(let defeated, let victor):
            flashBanner("⚡ \(defeated.displayName)国灭，归\(victor.displayName)方")
            updateStatus()
            triggerAIIfNeeded()
        case .cleared(let defeated):
            flashBanner("💨 \(defeated.displayName)国消极，清空灭国")
            updateStatus()
            triggerAIIfNeeded()
        case .noMovesDefeated(let defeated, let victor):
            flashBanner("困毙：\(defeated.displayName)国无路可走，归\(victor.displayName)方")
            updateStatus()
            triggerAIIfNeeded()
        case .gameOver(let winner):
            flashBanner("🏆 \(winner.displayName)方一统天下！")
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
