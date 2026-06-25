//
//  GameViewController.swift
//  sanguochese
//
//  三国象棋 · 视图控制器
//
//  程序化创建 GameScene（不再依赖 GameScene.sks 模板），并按场景尺寸自适应。
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    /// 玩家阵营（人类操作）。默认空 = 人人对战。
    /// 由 SgSetupViewController 注入。
    var humanSides: Set<SgNation> = []
    /// AI 难度
    var aiDifficulty: SgDifficulty = .normal
    /// 是否启用 AI 解说
    var commentaryEnabled: Bool = false
    /// DeepSeek API Key（空 = 解说走兜底文案）
    var commentaryApiKey: String = ""
    /// 解说视角阵营
    var commentarySide: SgNation = .shu
    /// 棋盘视角阵营（该方地盘朝屏幕下方展开）；nil = 默认魏方在上
    var perspectiveSide: SgNation? = nil

    /// 当前已呈现的 scene（避免重复 present）
    private var scenePresented = false

    /// 覆盖 loadView：把根视图设为 SKView，否则默认 UIView 会导致
    /// `view as? SKView` 失败 → 黑屏。
    override func loadView() {
        self.view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 视图尺寸在 viewDidLoad 阶段可能仍为 0（模态全屏 present），
        // 真正的 scene 创建放到 viewDidLayoutSubviews。
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !scenePresented else { return }
        let bounds = self.view.bounds
        // 等待非零尺寸
        guard bounds.width > 0 && bounds.height > 0 else { return }
        scenePresented = true

        guard let skView = self.view as? SKView else { return }

        let scene = GameScene(size: bounds.size)
        scene.scaleMode = .aspectFill
        scene.humanSides = humanSides
        scene.aiDifficulty = aiDifficulty
        scene.commentarySide = commentarySide
        scene.perspectiveSide = perspectiveSide
        if commentaryEnabled {
            scene.commentaryBridge = SgDeepSeekBridge(apiKey: commentaryApiKey)
        }

        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
