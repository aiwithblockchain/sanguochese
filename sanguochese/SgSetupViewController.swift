//
//  SgSetupViewController.swift
//  sanguochese
//
//  开局设置 · 统一入口（2 人标准象棋 / 3 人三国象棋）
//
//  顶层选择玩法：
//    - 2 人对弈（标准中国象棋规则，在三国棋盘上取两方对局）
//    - 3 人对弈（三国象棋，魏/蜀/吴）
//  统一创建 GameViewController，通过 SgGameMode 区分。
//
// 3 人模式选项：
//    - 对战模式：人人对战 / 人机对战
//    - 玩家阵营（人机模式）：魏 / 蜀 / 吴 / 旁观（三方皆 AI）
//    - AI 难度：简单 / 普通 / 困难 / 专家
//    - AI 解说（DeepSeek，可选）
//
// 2 人模式选项：
//    - 对战模式：人机对战 / 人人对战
//    - 玩家方（人机模式）：魏 / 蜀 / 吴（对手自动取下一国）
//    - AI 难度：简单 / 普通 / 困难 / 专家
//

import UIKit
import SgEngine

class SgSetupViewController: UIViewController {

    /// 当前玩法
    private var gameMode: GameMode = .threePlayer
    /// 选中的玩家阵营（3 人人机模式 / 2 人人机模式）。默认蜀。
    private var selectedHumanSide: SgNation = .shu
    /// 是否人人对战
    private var isHumanVsHuman = false
    /// AI 难度（2 人 / 3 人共用）
    private var difficulty: SgDifficulty = .normal
    /// 是否启用 AI 解说（仅 3 人）
    private var commentaryEnabled = false
    /// DeepSeek API Key（空 = 解说走兜底文案）
    private var apiKey: String = ""

    private enum GameMode {
        case twoPlayer
        case threePlayer
    }

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    /// 动态区容器：玩法切换时重建内部控件
    private let dynamicContainer = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        title = "开局设置"
        setupLayout()
        rebuildDynamicSection()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        contentStack.addArrangedSubview(makeTitleLabel("选择玩法"))
        contentStack.addArrangedSubview(makeGameModeSegment())

        dynamicContainer.axis = .vertical
        dynamicContainer.spacing = 24
        contentStack.addArrangedSubview(dynamicContainer)

        contentStack.addArrangedSubview(makeStartButton())
    }

    private func makeGameModeSegment() -> UISegmentedControl {
        let seg = UISegmentedControl(items: ["2 人对弈", "3 人对弈（三国）"])
        seg.selectedSegmentIndex = 1  // 默认三国（保留原行为）
        seg.addTarget(self, action: #selector(gameModeChanged(_:)), for: .valueChanged)
        return seg
    }

    @objc private func gameModeChanged(_ s: UISegmentedControl) {
        gameMode = s.selectedSegmentIndex == 0 ? .twoPlayer : .threePlayer
        rebuildDynamicSection()
    }

    /// 根据玩法重建动态选项区
    private func rebuildDynamicSection() {
        // 清空旧的
        for v in dynamicContainer.arrangedSubviews {
            dynamicContainer.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        switch gameMode {
        case .twoPlayer:
            dynamicContainer.addArrangedSubview(makeTitleLabel("对战模式"))
            dynamicContainer.addArrangedSubview(makeModeSegment())

            dynamicContainer.addArrangedSubview(makeTitleLabel("玩家方（对手自动取下一国）"))
            dynamicContainer.addArrangedSubview(makeNationPicker())

            dynamicContainer.addArrangedSubview(makeTitleLabel("AI 难度"))
            dynamicContainer.addArrangedSubview(makeDifficultySegment())

        case .threePlayer:
            dynamicContainer.addArrangedSubview(makeTitleLabel("对战模式"))
            dynamicContainer.addArrangedSubview(makeModeSegment())

            dynamicContainer.addArrangedSubview(makeTitleLabel("玩家阵营"))
            dynamicContainer.addArrangedSubview(makeNationPicker())

            dynamicContainer.addArrangedSubview(makeTitleLabel("AI 难度"))
            dynamicContainer.addArrangedSubview(makeDifficultySegment())

            dynamicContainer.addArrangedSubview(makeTitleLabel("AI 解说"))
            dynamicContainer.addArrangedSubview(makeCommentarySwitch())
            dynamicContainer.addArrangedSubview(makeApiKeyField())
        }
    }

    // MARK: - 对战模式（2 人 / 3 人共用）

    private func makeModeSegment() -> UISegmentedControl {
        let seg = UISegmentedControl(items: ["人机对战", "人人对战"])
        seg.selectedSegmentIndex = isHumanVsHuman ? 1 : 0
        seg.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        return seg
    }

    @objc private func modeChanged(_ s: UISegmentedControl) {
        isHumanVsHuman = s.selectedSegmentIndex == 1
    }

    // MARK: - 阵营选择（2 人 / 3 人共用）

    private func makeNationPicker() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        for nation in SgNation.allCases {
            let btn = NationButton(nation: nation)
            btn.addTarget(self, action: #selector(nationTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
        // 默认选中蜀
        (stack.arrangedSubviews.first { ($0 as? NationButton)?.nation == .shu } as? NationButton)?.isSelected = true
        return stack
    }

    @objc private func nationTapped(_ sender: NationButton) {
        selectedHumanSide = sender.nation
        for case let btn as NationButton in sender.superview?.subviews ?? [] {
            btn.isSelected = (btn === sender)
        }
    }

    // MARK: - 难度（2 人 / 3 人共用）

    private func makeDifficultySegment() -> UISegmentedControl {
        let seg = UISegmentedControl(items: SgDifficulty.allCases.map { $0.displayName })
        seg.selectedSegmentIndex = difficulty.rawValue
        seg.addTarget(self, action: #selector(difficultyChanged(_:)), for: .valueChanged)
        return seg
    }

    @objc private func difficultyChanged(_ s: UISegmentedControl) {
        if let d = SgDifficulty(rawValue: s.selectedSegmentIndex) {
            difficulty = d
        }
    }

    // MARK: - 解说开关（仅 3 人）

    private func makeCommentarySwitch() -> UISwitch {
        let sw = UISwitch()
        sw.isOn = commentaryEnabled
        sw.addTarget(self, action: #selector(commentaryToggled(_:)), for: .valueChanged)
        return sw
    }

    @objc private func commentaryToggled(_ s: UISwitch) {
        commentaryEnabled = s.isOn
    }

    private func makeApiKeyField() -> UITextField {
        let field = UITextField()
        field.placeholder = "DeepSeek API Key（可选，留空用兜底文案）"
        field.borderStyle = .roundedRect
        field.font = UIFont.systemFont(ofSize: 15)
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.addTarget(self, action: #selector(apiKeyChanged(_:)), for: .editingChanged)
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return field
    }

    @objc private func apiKeyChanged(_ f: UITextField) {
        apiKey = f.text ?? ""
    }

    // MARK: - 开始按钮

    private func makeStartButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("开始对弈", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        btn.backgroundColor = UIColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 12
        btn.heightAnchor.constraint(equalToConstant: 56).isActive = true
        btn.addTarget(self, action: #selector(startGame), for: .touchUpInside)
        return btn
    }

    @objc private func startGame() {
        switch gameMode {
        case .twoPlayer:
            startTwoPlayerGame()
        case .threePlayer:
            startThreePlayerGame()
        }
    }

    /// 2 人模式：human 与 ai = human.next() 两方对局。
    /// 人人对战时两方都由人类操作。
    private func startTwoPlayerGame() {
        let human = selectedHumanSide
        let ai = human.next()
        let gameVC = GameViewController()
        gameVC.gameMode = .twoNation(human: human, ai: ai)
        if isHumanVsHuman {
            gameVC.humanSides = [human, ai]
        } else {
            gameVC.humanSides = [human]
        }
        gameVC.aiDifficulty = difficulty
        // 视角：人机模式以玩家方为下方；人人对战默认 nil
        gameVC.perspectiveSide = isHumanVsHuman ? nil : human
        gameVC.modalPresentationStyle = .fullScreen
        present(gameVC, animated: true)
    }

    private func startThreePlayerGame() {
        let gameVC = GameViewController()
        gameVC.gameMode = .threeNation
        gameVC.humanSides = isHumanVsHuman ? [.wei, .shu, .wu] : [selectedHumanSide]
        gameVC.aiDifficulty = difficulty
        gameVC.commentaryEnabled = commentaryEnabled
        gameVC.commentaryApiKey = apiKey
        gameVC.commentarySide = selectedHumanSide
        // 视角：人机模式以玩家本国为下方；人人对战默认魏方在上（nil）
        gameVC.perspectiveSide = isHumanVsHuman ? nil : selectedHumanSide
        gameVC.modalPresentationStyle = .fullScreen
        present(gameVC, animated: true)
    }

    // MARK: - 辅助

    private func makeTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = UIColor(white: 0.2, alpha: 1.0)
        return label
    }
}

// MARK: - NationButton（2 人 / 3 人共用）

private class NationButton: UIButton {
    let nation: SgNation
    private let nationColor: UIColor

    init(nation: SgNation) {
        self.nation = nation
        switch nation {
        case .wei: nationColor = UIColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)
        case .shu: nationColor = UIColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1.0)
        case .wu:  nationColor = UIColor(red: 0.20, green: 0.70, blue: 0.40, alpha: 1.0)
        }
        super.init(frame: .zero)
        setTitle("\(nation.displayName) 方", for: .normal)
        titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        layer.cornerRadius = 10
        layer.borderWidth = 2
        heightAnchor.constraint(equalToConstant: 52).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        if isSelected {
            backgroundColor = nationColor
            setTitleColor(.white, for: .normal)
            layer.borderColor = nationColor.cgColor
        } else {
            backgroundColor = .white
            setTitleColor(nationColor, for: .normal)
            layer.borderColor = nationColor.withAlphaComponent(0.4).cgColor
        }
    }
}
