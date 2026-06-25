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

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = self.view as? SKView else { return }

        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .aspectFill
        scene.humanSides = humanSides
        scene.aiDifficulty = aiDifficulty
        scene.commentarySide = commentarySide
        if commentaryEnabled {
            scene.commentaryBridge = SgDeepSeekBridge(apiKey: commentaryApiKey)
        }

        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true
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
