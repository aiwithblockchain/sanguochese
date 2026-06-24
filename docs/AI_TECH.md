# 三国象棋 AI 技术方案

> 基于 `DESIGN.md` v0.2 的设计，调研开源引擎与多方博弈搜索算法后，确定的人机对战实现方案。

---

## 1. 调研结论速览

### 1.1 开源引擎评估

| 引擎 | 语言 | License | 三方可行性 | 参考价值 |
|---|---|---|---|---|
| **Pikafish** | C++ | GPL-3.0 | ❌ 不可行 | 低（只读借鉴） |
| **Fairy-Stockfish** | C++ | GPL-3.0 | ❌ 官方明确拒绝 | 中（走法对照） |
| **Eleeye 象眼** | C++/VB6 | LGPL-2.1 | ❌ 停更、查表硬编码 | 中（UCCI + genmoves 思路） |
| **moonfish** | Python | 待确认 | ✅ 偏移量式易改拓扑 | **高（走法生成抄思路）** |
| **wukong-xiangqi** | JS | MIT | ✅ 小巧易读 | **高（走法生成抄思路）** |
| **xiangqi.js** | JS | BSD-2 | ✅ 走法库 API 清晰 | 中 |
| **XiangqiNotebook** | Swift | MIT | ✅ 同语言 | **高（Swift 风格参考）** |
| **threeChess** | Java | MIT | ✅ 三方吃王制先例 | **高（三方结算参考）** |

### 1.2 关键事实

1. **没有任何开源引擎支持三方中国象棋。** Fairy-Stockfish 官方在 Issue #1 的 "Limitations (Not Doable)" 中明确将 "multiplayer variants" 列为架构性限制，不在路线图上。
2. **GPL-3.0 会传染 iOS 项目。** Pikafish、Fairy-Stockfish 源码不可直接引用（除非整个 App 开源）。
3. **Pikafish 的 bitboard + NNUE 深度绑定 9×10 两方几何。** 改 120° 三方对称需重写 bitboard 布局、重训 NNUE、重做走法表，工作量接近重写。
4. **三方国际象棋有先例**（threeChess，Java，MIT），采用"吃王即灭国"机制，与我们"吃帅即灭国"高度相似，可借鉴结算逻辑。
5. **Swift 象棋实现存在**（XiangqiNotebook），同语言参考价值最高。

### 1.3 核心决策

**不 fork 任何引擎，采用"自研框架 + 友好协议走法参考"路线。**

理由：
- 三方几何 + 国界分叉 + 吞并机制是本项目独有需求，任何引擎都帮不了这部分。
- 走法生成（车马炮象士帅兵的传统规则）是成熟逻辑，可从 moonfish / wukong / XiangqiNotebook 借鉴思路，用 Swift 重写。
- GPL 引擎强度对早期玩法验证无意义，且 license 风险高。

---

## 2. 整体架构

```
┌──────────────────────────────────────────────────┐
│                  UI 层 (SpriteKit)                │
│  棋盘渲染 · 点击交互 · 走子动画 · 高亮提示          │
└────────────┬─────────────────────────────────────┘
             │ 走子指令 / 局面更新
             ▼
┌──────────────────────────────────────────────────┐
│              规则层 (SanguoRules)                  │
│  棋盘坐标系 · 接线表σ · 分叉路由 · 走法生成         │
│  合法性校验 · 三方主帅互照 · 灭国吞并状态机         │
└────────────┬─────────────────────────────────────┘
             │ 合法走法集 / 局面
             ▼
┌──────────────────────────────────────────────────┐
│              AI 层 (SanguoAI)                      │
│  三方搜索 (MaxN/Paranoid) · 评估函数 · 难度调节    │
└────────────┬─────────────────────────────────────┘
             │ 选定走法
             ▼
┌──────────────────────────────────────────────────┐
│           解说层 (DeepSeekBridge)                  │
│  局面描述生成 · 角色prompt · API调用 · 对白渲染     │
└──────────────────────────────────────────────────┘
```

四层解耦，每层可独立开发和测试。

---

## 3. 规则层设计

### 3.1 棋盘坐标系统

**不用 bitboard，用哈希坐标。** 三瓣 120° 几何不适合位棋盘，用显式坐标更清晰。

```swift
// 坐标 = (国家, 线, 行)
struct SgPos: Hashable {
    let nation: SgNation   // .wei / .shu / .wu
    let file: Int          // 1...9  线
    let rank: Int          // 1...5  行（1=底线，5=国界边）
}

enum SgNation { case wei, shu, wu }
```

每方地盘 9×5 = 45 格，三方共 135 格。九宫范围由 (nation, file∈4..6, rank∈1..3) 确定。

### 3.2 接线表 σ（翻转对接）

```swift
// 我方线 i 进攻 target 国时，接对方线 (10 - i)
func route(myFile: Int, target: SgNation) -> Int {
    return 10 - myFile
}
```

过国界后，棋子从 `(me, file, 5)` 进入 `(target, 10-file, 1)`，继续按传统纵线走法。

### 3.3 走法生成（两层解耦）

**第一层：传统走法生成器** —— 给定一条 10 格纵线（己方 5 + 对方 5），生成棋子在该线上的传统走法。参考 moonfish / wukong 的偏移量逻辑，用 Swift 重写。

**第二层：分叉路由层** —— 当走法跨越国界时，沿两个方向各生成一份：

```swift
func moves(for piece: SgPiece, at pos: SgPos) -> [SgMove] {
    var result: [SgMove] = []
    // 1. 己方地盘内的走法（不过国界）
    result += traditionalMoves(piece, pos, crossBorder: false)
    // 2. 若棋子可过国界，沿两个方向各生成一份
    if canCrossBorder(piece) {
        for target in otherNations(of: pos.nation) {
            result += traditionalMoves(piece, pos, crossBorder: true, toward: target)
        }
    }
    return result
}
```

象/士/帅不过国界，只走第一层；车/马/炮/兵过国界，走两层。

### 3.4 三方主帅互照

对每方主帅，沿其通往另外两方的两条主线方向检查无遮挡相对。合法走法必须**同时解除两方照面**，否则该走法非法。若所有走法都无法同时解除，判灭国（借刀杀人）。

### 3.5 灭国吞并状态机

```swift
enum SgGameState {
    case threeNation   // 三国并存
    case twoNation     // 已灭一国，两方对弈
    case gameOver(winner: SgNation)
}

func applyMove(_ move: SgMove) {
    // 1. 执行走子（含吃子）
    // 2. 若吃到主帅 → 触发吞并
    //    - 败方所有棋子改色归胜方
    //    - 兵卒前进方向重指向剩余敌国
    //    - 状态转为 twoNation 或 gameOver
    // 3. 若某方无合法走法 → 判负灭国
    // 4. 若三国阶段某方无过河棋 → 判负清空
}
```

---

## 4. AI 层设计

### 4.1 算法选择

调研的三种多方搜索算法：

| 算法 | 原理 | 剪枝强度 | 适合度 | 复杂度 |
|---|---|---|---|---|
| **MaxN** | 每方独立最大化自身收益向量 | 弱 | 中 | O(b^d) |
| **Paranoid** | 假设所有对手联合对付自己 | 强（≈αβ） | 高（可复用αβ框架） | O(b^(d/2)) |
| **Best-Reply** | 只考虑最强对手的回应 | 中 | 中高 | 介于两者 |

**推荐：分阶段混合策略。**

- **三国阶段**：用 **Paranoid search**。理由：剪枝强、可复用成熟 αβ 框架、保守策略对玩家友好（AI 不会冒进送子）。虽然"对手联合"假设不完全成立，但三国阶段玩家本就面临多方压力，paranoid 的保守反而贴近体验。
- **两方阶段（灭国后）**：自动降级为**标准 αβ**。此时已是传统两方零和，直接用。
- **未来升级**：可切换到 Best-Reply 或 MaxN 提升进攻性。

### 4.2 评估函数

返回一个三维向量（三国阶段）或标量（两方阶段）：

```swift
struct SgEval {
    var wei: Int
    var shu: Int
    var wu: Int
}

func evaluate(_ board: SgBoard) -> SgEval {
    // 1. 子力价值（帅∞/车9/炮4.5/马4/象2/士2/兵1，参考传统象棋）
    // 2. 位置加成（中心线、过河兵、车占肋）
    // 3. 主帅安全（对两方分别计算威胁度）
    // 4. 机动性（合法走法数）
    // 5. 吞并威胁（若能一手吃帅，大幅加分）
}
```

子力价值表参考 Eleeye / 传统象棋经验值，再按三方平衡微调。

### 4.3 吞并在搜索树中的处理

吞并是状态突变，搜索树需特殊处理：

```swift
func search(_ node: SgNode, depth: Int) -> SgEval {
    if node.isJustAnnexed {
        // 吞并后局面重置：重新计算各方子力
        // 被灭方棋子归胜方，评估向量降维
        return evaluateAfterAnnex(node)
    }
    // 正常搜索...
}
```

吞并后，评估从三维降为二维（两方阶段），搜索自动切换为 αβ。

### 4.4 难度调节

```swift
enum SgDifficulty {
    case easy    // 深度2 + 30%随机走法
    case normal  // 深度3 + 10%随机
    case hard    // 深度4 + 置换表
    case expert  // 深度5+ + 迭代加深 + 杀手走法
}
```

不依赖引擎复杂机制，靠搜索深度 + 随机扰动实现，简单可控。

### 4.5 性能预期

- 深度 3（normal）：每步 < 1 秒（iPhone）。
- 深度 4（hard）：每步 1-3 秒。
- 深度 5+（expert）：需加置换表、迭代加深、并行搜索。

初版先跑通深度 2-3，能玩即可。

---

## 5. 解说层设计

### 5.1 DeepSeek 接入

```swift
struct DeepSeekBridge {
    let apiKey: String
    let endpoint = "https://api.deepseek.com/v1/chat/completions"
    let model = "deepseek-chat"

    func commentate(move: SgMove, board: SgBoard, role: SgRole) async -> String {
        let prompt = buildPrompt(move: move, board: board, role: role)
        // 调用 API，返回角色化点评
    }
}
```

### 5.2 角色 Prompt

三国角色分工：
- 玩家是蜀方 → 诸葛亮解说（鼓励 + 教学）
- AI 是魏方 → 曹操点评（威压 + 战术）
- AI 是吴方 → 周瑜点评（机锋 + 算计）

Prompt 模板包含：当前局面 FEN、刚走的步、角色人设、输出风格约束。

### 5.3 局面描述生成

把 SgBoard 序列化为自然语言描述喂给 LLM：
- 三方剩余子力对比
- 刚走的步及其战术意图（由规则层标注：是否吃子、是否将军、是否过河）
- 主帅安全状态

LLM 不参与走法决策，只做解说，避免幻觉影响对弈。

---

## 6. 开源参考清单

### 6.1 可直接借鉴代码（license 友好）

| 项目 | 语言 | License | 借鉴点 |
|---|---|---|---|
| wukong-xiangqi | JS | MIT | 走法生成核心逻辑 |
| moonfish | Python | 待确认 | 偏移量式走法，易改拓扑 |
| xiangqi.js | JS | BSD-2 | 走法库 API 形状 |
| threeChess | Java | MIT | 三方轮转 + 吃王灭国结算 |
| XiangqiNotebook | Swift | MIT | Swift 象棋代码风格、FEN、MoveRules |
| LudiiExampleAI | Java | MIT | UCT/DUCT 多方搜索参考 |

### 6.2 只读借鉴（不可引用源码）

| 项目 | 原因 | 借鉴点 |
|---|---|---|
| Pikafish | GPL-3.0 | 搜索/评估深度技术思路 |
| Fairy-Stockfish | GPL-3.0 | 变体配置化架构、Betza 记谱 |
| Eleeye | LGPL-2.1 | UCCI 协议、genmoves/pregen 分离 |

### 6.3 学术参考

1. Sturtevant & Korf, "On Pruning Techniques for Multi-Player Games," AAAI-00, 2000.
2. Sturtevant, "A Comparison of Algorithms for Multi-player Games," Computers and Games 2003, LNCS 2883.
3. Schadd et al., "Best-Reply Search for Multiplayer Games," Computers and Games 2008, LNCS 5131.
4. Wikipedia: [Multiplayer game tree search](https://en.wikipedia.org/wiki/Multiplayer_game_tree_search)

---

## 7. 实现路线

### 阶段 1：规则闭环（无 AI，无 UI）
1. 棋盘坐标 + 接线表 σ + 分叉路由
2. 棋子模型 + 三方初始布局
3. 走法生成（传统 + 分叉）
4. 合法性校验 + 三方主帅互照
5. 灭国吞并状态机
6. 单元测试：用两两对局验证走法与传统象棋一致

### 阶段 2：UI + 人人对战
7. SpriteKit 棋盘渲染（三瓣 + 中央交汇）
8. 点击交互 + 走子动画
9. 合法走法高亮
10. 灭国/胜负 UI 反馈

### 阶段 3：人机对战
11. Paranoid search（三国阶段）
12. αβ search（两方阶段）
13. 评估函数
14. 难度调节
15. 跑通人机对战闭环

### 阶段 4：解说层
16. DeepSeek 接入
17. 角色 prompt + 局面描述
18. 对白渲染

### 阶段 5：优化
19. 置换表、迭代加深、杀手走法
20. 评估函数调优
21. 可选：升级到 Best-Reply / MaxN

---

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 三方几何坐标易出错 | 阶段 1 用单元测试覆盖，两两对局与传统象棋对照 |
| Paranoid 过于保守 | 先跑通，后续切 Best-Reply 提升进攻性 |
| 吞并后评估跳变 | 专门处理 isJustAnnexed 节点，重新评估 |
| DeepSeek 延迟/成本 | 解说异步生成，不阻塞走子；缓存角色 prompt |
| Swift 象棋参考少 | XiangqiNotebook + wukong 思路移植 |
| GPL 传染 | 严格不引用 GPL 源码，只读借鉴思路 |

---

*文档版本：v0.1 · 2026-06-24*
