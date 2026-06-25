# 三国象棋 · 算法重构与后续开发计划

> 版本：v1.0 · 2026-06-25
> 状态：规划中（待评审后实施）

---

## 一、问题诊断

### 1.1 棋力缺陷（"AI 弱智"）

当前 AI 在 3 人阶段表现极差，根因有三层：

| 层级 | 问题 | 表现 |
|---|---|---|
| **搜索模型** | Paranoid 把两个对手建模为"联合最小化我方收益"的零和联盟。实际上对手之间也会互相攻击，Paranoid 系统性高估威胁、低估机会，导致 AI 过度防守、不敢出击。 | AI 把所有对手当成合谋，错判局势。 |
| **搜索深度** | 困难档 depth=4、专家档 depth=5，但每层分支因子 ~40+（三方轮转），实际有效深度只有 2-3 ply。看不到战术组合。 | 看不到 2 步以后的吃子/将军。 |
| **评估函数** | `SgEval` 只算子力+粗位置+机动性，且**机动性每次都调用 `legalMoves` 全量生成**——评估本身 O(N·分支) 极贵，进一步压低搜索深度。位置表过于粗糙（仅"过河兵+15""车占肋+10"），无九宫防御、无车马炮协同、无兵卒推进梯度。 | 评估噪声大，搜索选不出好走法。 |

### 1.2 性能缺陷（"思考很慢"）

| 瓶颈 | 现状 | 影响 |
|---|---|---|
| **全量快照** | 搜索每个节点用 `Snapshot.take/restore` 复制整个 `pieces` 字典（135 项）+ aliveNations + annexed。 | 每节点一次字典全拷贝，深度 5 时上百万次拷贝，是最大性能杀手。 |
| **Zobrist 全量重算** | `SgZobrist.hash(of:)` 每次遍历全部棋子重算，没有增量更新。 | 每节点 O(N) 哈希，本可 O(1)。 |
| **走法生成重复** | `legalMoves` 内部对每个伪合法走法 `apply/undo` 检查主帅照面，再在搜索里又 `Snapshot.take/play/restore`。同一走法做了两遍 apply/undo。 | 分支因子翻倍。 |
| **评估内 legalMoves** | `SgEvaluator.score` 调 `legalMoves` 算机动性，叶节点评估时又生成一遍走法。 | 叶节点开销 ≈ 内部节点。 |
| **无 quiescence** | 搜索在 depth=0 立即返回评估，吃子序列未延伸。 | horizon effect：刚好吃亏的走法被当成好走法。 |
| **无 late-move reduction / null-move** | 标准优化缺失。 | 搜索树未被有效剪枝。 |

---

## 二、重构方案（阶段 A：2 人模式 + 性能重构）

### 2.1 核心思路

**先用 1v1（人 vs 1 个 AI）作为算法验证场**，原因：

1. 1v1 是标准零和 αβ，模型正确，不存在 Paranoid 的系统性偏差。
2. 1v1 分支因子 ≈ 传统象棋（~35），现有优化手段（TT/迭代加深/quiescence/LMR/null-move）可直接验证效果。
3. 1v1 棋力可对标传统象棋引擎，有客观基准。
4. 算法稳定后再扩展到 3 人（1 人 vs 2 AI），届时只需把 1v1 的 αβ 包成 max-n 或改良的 Paranoid/MaxN-αβ。

**2 人模式规则简化**：取魏蜀两方，去掉吴方地盘（或保留地盘但无棋子、不可走）。国界分叉退化为单条对接线（与传统象棋完全一致）。判负：吃帅 / 无子可走 / 消极判负（无过河棋且对方有过河棋）。

### 2.2 性能重构清单

#### A. make/unmake 增量走子（替代全量快照）

```swift
// 新增 SgBoard.make(_:) / unmake(_:with:)
// make: 记录 (move, capturedPiece, sideToMoveBefore, aliveNationsDelta?, annexedDelta?)
//       只改 pieces[from]/pieces[to]，不复制字典
// unmake: 用记录的信息逆操作
```

- 走子不触发吞并时：make/unmake 只动 2 个字典项，O(1)。
- 走子触发吞并（吃帅）：吞并是少见事件，仍可用快照，但单独走"重做"路径，不污染主路径性能。
- 搜索层 `Snapshot` 退役，改为 `make/unmake`。

#### B. 增量 Zobrist

```swift
// SgBoard 持有 var zobrist: UInt64
// make 时：zobrist ^= pieceKeys[from][mover] ^ pieceKeys[to][mover] ^ pieceKeys[to][captured?] ^ sideKeys[side] ^ sideKeys[next]
// unmake 时：异或回退（异或自反）
// 吞并时：重算（少见，可接受）
```

搜索节点直接读 `board.zobrist`，O(0)。

#### C. quiescence 搜索

```swift
static func quiescence(board, alpha, beta, context) -> Int {
    let standPat = evaluate(board)
    if standPat >= beta { return beta }
    if standPat > alpha { alpha = standPat }
    for move in captureMovesOnly(board) {  // 只生成吃子走法
        make(move)
        let score = -quiescence(board, -beta, -alpha, context)
        unmake(move)
        if score >= beta { return beta }
        if score > alpha { alpha = score }
    }
    return alpha
}
```

- depth=0 时不直接返回评估，而是进 quiescence。
- 只延伸吃子走法（含吃帅），避免无限延伸。
- 解决 horizon effect，是棋力提升最关键的一步。

#### D. 评估函数提速 + 调优

- **去掉评估内的 `legalMoves` 调用**：机动性改为用伪合法走法数（不检查照面），或干脆去掉机动性项（传统象棋引擎大多不用）。
- **位置表细化**：每种棋子一张 9×5 表，按 (file, rank) 查分。过河兵按深入程度梯度加分（rank 越接近敌底线越高）。车马炮增加"控制中央"加分。
- **兵卒升变/过河奖励**：过河兵 +20，每深入 1 rank 再 +5。
- **主帅安全**：九宫内士象完整度检查，缺士缺象扣分。

#### E. 走法生成与合法性合并

- 搜索内部用 `pseudoLegalMoves` + make/unmake + 照面检查，避免 `legalMoves` 的二次 apply/undo。
- 或：`legalMoves` 改为生成时直接用 make/unmake（而非 apply/undo），减少一次拷贝。

#### F. 其他优化（可选，后续迭代）

- **Late Move Reduction (LMR)**：排序靠后的走法在非 PV 节点降深度搜索。
- **Null-Move Pruning**：跳过一手，若仍 > β 则剪枝（需评估函数支持"空走"）。
- **Killer Move 升级**：当前已实现 2 槽，可扩到 4 槽。
- **History Malus**：对失败走法减历史分（当前只加不减）。

### 2.3 2 人模式实现

#### 模式枚举

```swift
public enum SgGameMode {
    case threeNation      // 三国（原模式）
    case twoNation(human: SgNation, ai: SgNation)  // 1v1
}
```

#### 棋盘初始化

- `SgLayout.initialBoard(mode: .twoNation(human: .shu, ai: .wei))`：只摆两方棋子，第三方地盘留空。
- `SgNation.allCases` 在两方模式下应过滤为两方（需要 `board.aliveNations` 一开始就只有两方）。

#### 走法生成适配

- `outRays`/`inRays` 在两方模式下分叉目标只剩 1 个敌国，自然退化为单条射线，无需改几何。
- `opponents()` 在两方模式下返回 1 个敌国（已由 `aliveNations` 过滤，但 `SgNation.opponents()` 是静态的——需在走法生成层用 `board.aliveNations` 过滤）。

#### 搜索适配

- 两方模式直接走 `alphabeta`（已实现），不走 `paranoid`。
- `relative(for:alive:)` 在两方时 = mine - enemy，等价于标准 negamax 评估。

#### UI 适配

- `SgSetupViewController` 新增"2 人对战 / 3 人对战"模式选择。
- 2 人模式选阵营后，`perspectiveSide = humanSide`，另一方 = AI。
- `GameScene.humanSides = [human]`，AI 接管另一方。
- 棋盘渲染：第三方地盘画成虚化/灰色（可选），或直接不画（更简洁）。

---

## 三、实施步骤

### 阶段 A-1：性能基础设施（不改外部行为）

1. **SgBoard 增加 make/unmake + 增量 Zobrist**
   - 新增 `make(_:) -> SgMoveRecord`、`unmake(_:with:)`
   - `SgMoveRecord` 记录 move + captured + 旧 sideToMove + 吞并标记
   - 吞并场景仍走快照路径（少见）
   - `var zobrist: UInt64` 在 make/unmake 时增量更新
2. **SgSearch 改用 make/unmake**
   - `Snapshot.take/restore` 替换为 `make/unmake`
   - TT 查询用 `board.zobrist` 而非 `SgZobrist.hash(of:)`
3. **quiescence 搜索**
   - 新增 `quiescence(board:alpha:beta:context:)`
   - `alphabeta` 和 `paranoid` 在 depth<=0 时调用 quiescence
   - 走法生成器新增 `captureMoves(for:on:)`（只生成吃子走法，用于 quiescence）
4. **评估函数提速**
   - 去掉 `SgEvaluator.score` 内的 `legalMoves` 调用
   - 机动性改为可选（默认关），或用伪合法走法数

**验证**：构建通过 + 3 人模式行为不变（走法、判负、吞并仍正确）+ 思考时间明显下降。

### 阶段 A-2：2 人模式

5. **SgGameMode 枚举 + SgLayout 两方初始化**
6. **走法生成在两方模式下用 aliveNations 过滤分叉目标**
7. **SgSearch 在两方模式走 alphabeta**
8. **SgSetupViewController 新增模式选择**
9. **GameScene/GameViewController 适配两方模式**

**验证**：2 人模式可正常对弈，AI 棋力明显优于原 3 人模式。

### 阶段 A-3：评估调优 + 棋力验证

10. **位置表细化**（每种棋子一张表）
11. **兵卒过河梯度奖励**
12. **主帅安全（士象完整度）**
13. **LMR / Null-Move（可选）**
14. **2 人模式棋力自测**：AI vs AI 对局、AI vs 人类盲测

---

## 四、后续开发（阶段 B：3 人算法升级）

阶段 A 验证 1v1 棋力达标后，再回到 3 人：

1. **MaxN-αβ 替代 Paranoid**：每个玩家最大化自己的绝对分，用 αβ 剪枝。比 Paranoid 更符合实际多方博弈。
2. **对手建模**：对手不总是"联合"，而是各自理性。可用 `max-n` with `shallow pruning`。
3. **联盟动态判断**：当一方明显领先时，另两方形成临时联盟（可由评估函数的"领先度"触发）。
4. **3 人专属战术**：坐山观虎斗、借刀杀人、驱虎吞狼——这些需在评估函数加入"对手互耗奖励"。

---

## 五、风险与回退

- **make/unmake 复杂度**：吞并场景的 make/unmake 较复杂（需回滚 aliveNations + annexed + 改色）。方案：吞并走特殊路径，make 时记录"是否触发吞并"，unmake 时若触发则走快照恢复。性能关键路径（非吞并走子）保持 O(1)。
- **增量 Zobrist 与吞并冲突**：吞并改色会改变多枚棋子的归属，增量更新麻烦。方案：吞并时重算 Zobrist（吞并是少见事件，可接受）。
- **2 人模式与 3 人模式代码分叉**：尽量复用，差异通过 `board.aliveNations.count` 分支，避免维护两套代码。
- **回退**：所有改动在 git 分支进行，每阶段独立 commit，可随时回退。

---

## 六、验收标准

| 阶段 | 验收项 |
|---|---|
| A-1 | 思考时间下降 ≥50%（同深度），走法/判货行为不变 |
| A-2 | 2 人模式可完整对弈至终局，无崩溃，无非法走法 |
| A-3 | 2 人模式 AI 棋力：不会送子、能看 3 步以上战术组合、能基本防守 |
| B | 3 人模式 AI 不再"弱智"，能合理出击与防守 |

---

*文档版本：v1.0 · 2026-06-25*
