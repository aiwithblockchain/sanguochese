//
//  TnGameViewController.swift
//  sanguochese
//
//  2 人标准中国象棋 · 视图控制器
//
//  程序化创建 TnGameScene，按场景尺寸自适应。
//  与 GameViewController 完全独立（Tn* 类型）。
//

import UIKit
import SpriteKit
import GameplayKit

class TnGameViewController: UIViewController {

    /// 人类操作的方。默认 [.red]（人机模式人类走红）。
    /// 人人对战 = [.red, .black]。
    var humanColors: Set<TnColor> = [.red]
    /// AI 难度
    var aiDifficulty: TnDifficulty = .normal
    /// 棋盘视角：该方在屏幕下方。nil = 红方在下（默认）。
    var perspectiveColor: TnColor? = nil

    /// 当前已呈现的 scene（避免重复 present）
    private var scenePresented = false

    /// 覆盖 loadView：把根视图设为 SKView。
    override func loadView() {
        self.view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !scenePresented else { return }
        let bounds = self.view.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }
        scenePresented = true

        guard let skView = self.view as? SKView else { return }

        let scene = TnGameScene(size: bounds.size)
        scene.scaleMode = .aspectFill
        scene.humanColors = humanColors
        scene.aiDifficulty = aiDifficulty
        scene.perspectiveColor = perspectiveColor

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
