//
//  SgSearch.swift
//  sanguochese
//
//  三国象棋 · 搜索引擎 (P5-2 / P5-3 / P5-4 / P5-5 / P7-1)
//
//  分阶段混合策略：
//    - 三国阶段（3 方存活）：Paranoid search
//      假设所有对手联合对付当前搜索方，可复用 αβ 框架。
//    - 两方阶段（灭国后）：标准 αβ。
//    - 吞并突变（P5-4）：在 play 之后若存活方数变化，重新评估并降维。
//
//  P7-1 性能优化：
//    - 置换表（SgTranspositionTable + SgZobrist）
//    - 迭代加深（从深度 1 递增到目标深度，用上一轮 PV 排序）
//    - 杀手走法（每个深度槽记 2 个引起 β cutoff 的走法）
//    - 历史启发（to 格 × from 格 的命中计数排序）
//

import Foundation

/// 难度档位（P5-5）
public enum SgDifficulty: Int, CaseIterable {
    case easy    = 0   // 深度 2 + 30% 随机
    case normal  = 1   // 深度 3 + 10% 随机
    case hard    = 2   // 深度 4
    case expert  = 3   // 深度 5 + 迭代加深 + 置换表

    /// 搜索深度（plies）
    public var depth: Int {
        switch self {
        case .easy:   return 2
        case .normal: return 3
        case .hard:   return 4
        case .expert: return 5
        }
    }

    /// 走随机走法的概率（0...1）
    public var randomChance: Double {
        switch self {
        case .easy:   return 0.30
        case .normal: return 0.10
        case .hard:   return 0.0
        case .expert: return 0.0
        }
    }

    /// 是否启用高级优化（置换表/迭代加深/杀手走法）
    public var useAdvancedOptimizations: Bool {
        return self == .expert
    }

    public var displayName: String {
        switch self {
        case .easy:   return "简单"
        case .normal: return "普通"
        case .hard:   return "困难"
        case .expert: return "专家"
        }
    }
}

/// 搜索结果
public struct SgSearchResult {
    public let move: SgMove?
    public let score: Int
    public let principalVariation: [SgMove]

    public init(move: SgMove?, score: Int, principalVariation: [SgMove]) {
        self.move = move
        self.score = score
        self.principalVariation = principalVariation
    }
}

/// P7-1：搜索上下文 —— 在一次 chooseMove 调用内共享的优化结构。
/// 单线程使用（后台搜索线程独占），无需加锁。
final class SgSearchContext {
    /// 置换表
    let tt: SgTranspositionTable
    /// 杀手走法：killerMoves[depth] -> (slot0, slot1)
    /// 深度上限 64 足够。
    var killerMoves: [(SgMove?, SgMove?)]
    /// 历史启发：history[fromIndex][toIndex] -> score
    /// 用 9×9 的 from/to 文件索引近似（rank 不参与，简化）。
    /// 实际用 90×90 的 from-to 一维索引（posIndex × 90 + posIndex）。
    var history: [Int]
    /// 当前搜索的目标深度（用于 killer 槽索引）
    var maxDepth: Int = 0

    init() {
        self.tt = SgTranspositionTable()
        self.killerMoves = Array(repeating: (nil, nil), count: 64)
        self.history = Array(repeating: 0, count: 90 * 90)
    }

    /// 清空所有增量状态（每次 chooseMove 调用前清空，避免跨局面污染）。
    func reset() {
        tt.clear()
        killerMoves = Array(repeating: (nil, nil), count: 64)
        history = Array(repeating: 0, count: 90 * 90)
    }

    /// 记录一个杀手走法（在 depth 层引起 β cutoff 的非吃子走法）。
    func recordKiller(_ move: SgMove, depth: Int) {
        let idx = max(0, min(killerMoves.count - 1, depth))
        let (s0, s1) = killerMoves[idx]
        if s0 == nil || s0! == move {
            killerMoves[idx] = (move, s1)
        } else if s1 == nil || s1! == move {
            killerMoves[idx] = (s0, move)
        } else {
            // 淘汰 slot1，新走法进 slot0
            killerMoves[idx] = (move, s0)
        }
    }

    /// 判断走法是否是某层的杀手走法。
    func isKiller(_ move: SgMove, depth: Int) -> Bool {
        let idx = max(0, min(killerMoves.count - 1, depth))
        let (s0, s1) = killerMoves[idx]
        return s0 == move || s1 == move
    }

    /// 历史走法加分。
    func addHistory(_ move: SgMove, depth: Int) {
        let fi = SgSearchContext.posLinearIndex(move.from)
        let ti = SgSearchContext.posLinearIndex(move.to)
        let key = fi * 90 + ti
        history[key] &+= depth * depth
    }

    /// 读取历史分。
    func historyScore(_ move: SgMove) -> Int {
        let fi = SgSearchContext.posLinearIndex(move.from)
        let ti = SgSearchContext.posLinearIndex(move.to)
        return history[fi * 90 + ti]
    }

    /// pos -> 0..89 线性索引（nation*30 + (file-1)*5 + (rank-1)）
    static func posLinearIndex(_ p: SgPos) -> Int {
        return p.nation.rawValue * 30 + (p.file - 1) * 5 + (p.rank - 1)
    }
}

public enum SgSearch {

    /// 为 `side` 选定一步走法。
    /// - Parameters:
    ///   - side: 当前应走方（必须与 board.sideToMove 一致）
    ///   - board: 局面（不会被修改）
    ///   - difficulty: 难度
    public static func chooseMove(for side: SgNation,
                                  on board: SgBoard,
                                  difficulty: SgDifficulty = .normal) -> SgSearchResult {
        let moves = SgLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            return SgSearchResult(move: nil, score: 0, principalVariation: [])
        }

        // 随机扰动：以 randomChance 概率直接随机走（模拟"失误"）
        if difficulty.randomChance > 0,
           Double.random(in: 0...1) < difficulty.randomChance {
            let pick = moves.randomElement()!
            return SgSearchResult(move: pick, score: 0, principalVariation: [pick])
        }

        if difficulty.useAdvancedOptimizations {
            return iterativeDeepening(for: side, on: board, maxDepth: difficulty.depth, moves: moves)
        }
        return searchRoot(for: side, on: board, depth: difficulty.depth, moves: moves, context: nil)
    }

    // MARK: - 迭代加深（P7-1）

    /// 从深度 1 递增到 maxDepth，每轮用上一轮的 PV 走法作为排序先导。
    /// 时间预算近似：每轮搜索完成后检查是否已超过软时限，超过则停止。
    static func iterativeDeepening(for side: SgNation,
                                   on board: SgBoard,
                                   maxDepth: Int,
                                   moves: [SgMove]) -> SgSearchResult {
        let context = SgSearchContext()
        context.maxDepth = maxDepth
        context.reset()

        var lastResult = SgSearchResult(move: moves[0], score: 0, principalVariation: [moves[0]])
        let startTime = Date()

        for depth in 1...maxDepth {
            let result = searchRoot(for: side,
                                    on: board,
                                    depth: depth,
                                    moves: moves,
                                    context: context,
                                    pvHint: lastResult.principalVariation)
            if let m = result.move {
                lastResult = result
            }
            // 软时限：每轮若超过 1.5s 则停止加深（近似，避免 UI 卡顿）
            if Date().timeIntervalSince(startTime) > 1.5 {
                break
            }
        }
        return lastResult
    }

    // MARK: - 根节点搜索

    /// 根节点：枚举所有合法走法，取最优。
    /// 三国阶段用 Paranoid（相对分 αβ），两方阶段用标准 αβ。
    static func searchRoot(for side: SgNation,
                           on board: SgBoard,
                           depth: Int,
                           moves: [SgMove],
                           context: SgSearchContext?,
                           pvHint: [SgMove] = []) -> SgSearchResult {
        let isThreeNation = board.aliveNations.count >= 3
        // 根节点对走法排序：PV 先导 + 吃子优先
        var ordered = orderMoves(moves, on: board, context: context, depth: depth)
        if !pvHint.isEmpty {
            // 把 PV 首步移到最前
            let pvFirst = pvHint[0]
            if let idx = ordered.firstIndex(of: pvFirst) {
                ordered.remove(at: idx)
                ordered.insert(pvFirst, at: 0)
            }
        }

        var bestMove: SgMove? = nil
        var bestScore = Int.min + 1
        var bestPV: [SgMove] = []
        var alpha = Int.min + 1
        let beta = Int.max - 1

        for move in ordered {
            let snapshot = Snapshot.take(from: board)
            let outcome = SgGameFlow.play(move, on: board)

            var childPV: [SgMove] = []
            let score: Int
            if case .gameOver(let winner) = outcome {
                score = terminalScore(for: side, winner: winner)
            } else if isThreeNation {
                score = -paranoid(board: board,
                                  rootSide: side,
                                  depth: depth - 1,
                                  alpha: -beta,
                                  beta: -alpha,
                                  pv: &childPV,
                                  context: context)
            } else {
                score = -alphabeta(board: board,
                                   rootSide: side,
                                   depth: depth - 1,
                                   alpha: -beta,
                                   beta: -alpha,
                                   pv: &childPV,
                                   context: context)
            }

            Snapshot.restore(snapshot, to: board)

            if score > bestScore {
                bestScore = score
                bestMove = move
                bestPV = [move] + childPV
            }
            if bestScore > alpha {
                alpha = bestScore
            }
        }

        // 存入置换表
        if let ctx = context {
            let hash = SgZobrist.hash(of: board)
            ctx.tt.store(SgTTEntry(key: hash,
                                   depth: depth,
                                   score: bestScore,
                                   flag: .exact,
                                   bestMove: bestMove))
        }

        return SgSearchResult(move: bestMove, score: bestScore, principalVariation: bestPV)
    }

    // MARK: - Paranoid 搜索（三国阶段）
    //
    // 关键映射：把多方博弈压成"当前应走方 vs 联盟"的零和。
    // 评估值 = currentSide.relative - 0（对手被建模为最小化该值）。
    // 由于回合切换到对手时，对手也在最大化"自己的相对分"，
    // 等价于最小化"rootSide 的相对分"——所以统一用 negamax 形式：
    //   score(side) = relative(side) ，递归取负。
    //
    // 这是对 Sturtevant Paranoid 的标准实现：所有非 rootSide 方
    // 被视为一个"联盟"，联盟的收益 = -rootSide 收益。
    //
    static func paranoid(board: SgBoard,
                         rootSide: SgNation,
                         depth: Int,
                         alpha: Int,
                         beta: Int,
                         pv: inout [SgMove],
                         context: SgSearchContext?) -> Int {
        // 终局
        if case .gameOver(let winner) = SgGameFlow.result(of: board) {
            return terminalScore(for: rootSide, winner: winner)
        }
        if depth <= 0 {
            return relativeScore(for: rootSide, on: board)
        }

        // P7-1：置换表查询
        let hash = SgZobrist.hash(of: board)
        if let ctx = context, let entry = ctx.tt.probe(hash) {
            if entry.depth >= depth {
                switch entry.flag {
                case .exact:
                    if let m = entry.bestMove { pv = [m] }
                    return entry.score
                case .lowerBound:
                    if entry.score >= beta {
                        if let m = entry.bestMove { pv = [m] }
                        return entry.score
                    }
                case .upperBound:
                    if entry.score <= alpha {
                        if let m = entry.bestMove { pv = [m] }
                        return entry.score
                    }
                }
            }
        }

        let side = board.sideToMove
        let moves = SgLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            return side == rootSide ? -SgEvaluator.kingValue : SgEvaluator.kingValue
        }

        let ordered = orderMoves(moves, on: board, context: context, depth: depth,
                                  ttMove: context?.tt.probe(hash)?.bestMove)
        var a = alpha
        var b = beta
        var best = Int.min + 1
        var bestMove: SgMove? = nil
        var raisedAlpha = false

        for move in ordered {
            let snapshot = Snapshot.take(from: board)
            let outcome = SgGameFlow.play(move, on: board)
            var childPV: [SgMove] = []
            let score: Int
            if case .gameOver(let winner) = outcome {
                score = terminalScore(for: rootSide, winner: winner)
            } else {
                score = -paranoid(board: board,
                                  rootSide: rootSide,
                                  depth: depth - 1,
                                  alpha: -b,
                                  beta: -a,
                                  pv: &childPV,
                                  context: context)
            }
            Snapshot.restore(snapshot, to: board)

            if score > best {
                best = score
                bestMove = move
                pv = [move] + childPV
            }
            if best > a {
                a = best
                raisedAlpha = true
            }
            if a >= b {
                // β cutoff：记录杀手走法与历史
                if context != nil && board.piece(at: move.to) == nil {
                    context?.recordKiller(move, depth: depth)
                }
                context?.addHistory(move, depth: depth)
                // 存为下界
                if let ctx = context {
                    ctx.tt.store(SgTTEntry(key: hash, depth: depth, score: best,
                                            flag: .lowerBound, bestMove: bestMove))
                }
                return best
            }
        }

        // 存入置换表
        if let ctx = context {
            let flag: SgTTFlag = raisedAlpha ? .exact : .upperBound
            ctx.tt.store(SgTTEntry(key: hash, depth: depth, score: best,
                                    flag: flag, bestMove: bestMove))
        }
        return best
    }

    // MARK: - αβ 搜索（两方阶段）
    //
    // 标准 negamax：score = -search(opponent)。
    // 评估值 = relativeScore(for: rootSide)。
    //
    static func alphabeta(board: SgBoard,
                          rootSide: SgNation,
                          depth: Int,
                          alpha: Int,
                          beta: Int,
                          pv: inout [SgMove],
                          context: SgSearchContext?) -> Int {
        if case .gameOver(let winner) = SgGameFlow.result(of: board) {
            return terminalScore(for: rootSide, winner: winner)
        }
        if depth <= 0 {
            return relativeScore(for: rootSide, on: board)
        }

        // P7-1：置换表查询
        let hash = SgZobrist.hash(of: board)
        if let ctx = context, let entry = ctx.tt.probe(hash) {
            if entry.depth >= depth {
                switch entry.flag {
                case .exact:
                    if let m = entry.bestMove { pv = [m] }
                    return entry.score
                case .lowerBound:
                    if entry.score >= beta {
                        if let m = entry.bestMove { pv = [m] }
                        return entry.score
                    }
                case .upperBound:
                    if entry.score <= alpha {
                        if let m = entry.bestMove { pv = [m] }
                        return entry.score
                    }
                }
            }
        }

        let side = board.sideToMove
        let moves = SgLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            return side == rootSide ? -SgEvaluator.kingValue : SgEvaluator.kingValue
        }

        let ordered = orderMoves(moves, on: board, context: context, depth: depth,
                                  ttMove: context?.tt.probe(hash)?.bestMove)
        var a = alpha
        var b = beta
        var best = Int.min + 1
        var bestMove: SgMove? = nil
        var raisedAlpha = false

        for move in ordered {
            let snapshot = Snapshot.take(from: board)
            let outcome = SgGameFlow.play(move, on: board)
            var childPV: [SgMove] = []
            let score: Int
            if case .gameOver(let winner) = outcome {
                score = terminalScore(for: rootSide, winner: winner)
            } else {
                score = -alphabeta(board: board,
                                   rootSide: rootSide,
                                   depth: depth - 1,
                                   alpha: -b,
                                   beta: -a,
                                   pv: &childPV,
                                   context: context)
            }
            Snapshot.restore(snapshot, to: board)

            if score > best {
                best = score
                bestMove = move
                pv = [move] + childPV
            }
            if best > a {
                a = best
                raisedAlpha = true
            }
            if a >= b {
                if context != nil && board.piece(at: move.to) == nil {
                    context?.recordKiller(move, depth: depth)
                }
                context?.addHistory(move, depth: depth)
                if let ctx = context {
                    ctx.tt.store(SgTTEntry(key: hash, depth: depth, score: best,
                                            flag: .lowerBound, bestMove: bestMove))
                }
                return best
            }
        }

        if let ctx = context {
            let flag: SgTTFlag = raisedAlpha ? .exact : .upperBound
            ctx.tt.store(SgTTEntry(key: hash, depth: depth, score: best,
                                    flag: flag, bestMove: bestMove))
        }
        return best
    }

    // MARK: - 评估与终局

    /// rootSide 视角的相对分：mine - max(opponents)。
    /// 用于 negamax 的叶节点。
    static func relativeScore(for rootSide: SgNation, on board: SgBoard) -> Int {
        let eval = SgEvaluator.evaluate(board)
        return eval.relative(for: rootSide, alive: board.aliveNations)
    }

    /// 终局分：rootSide 获胜 → +∞，失败 → -∞。
    static func terminalScore(for rootSide: SgNation, winner: SgNation) -> Int {
        return winner == rootSide ? (Int.max - 1) : (Int.min + 1)
    }

    // MARK: - 走法排序（吃子优先 + 置换表/杀手/历史，提升剪枝）

    /// 走法排序优先级：
    ///   1. 置换表建议走法（TT-move）最前
    ///   2. 吃子（MVV-LVA：被吃子价值 - 吃子价值/10）
    ///   3. 杀手走法（非吃子）
    ///   4. 历史启发分
    static func orderMoves(_ moves: [SgMove],
                           on board: SgBoard,
                           context: SgSearchContext?,
                           depth: Int,
                           ttMove: SgMove? = nil) -> [SgMove] {
        return moves.sorted { a, b in
            scoreMove(a, on: board, context: context, depth: depth, ttMove: ttMove)
                > scoreMove(b, on: board, context: context, depth: depth, ttMove: ttMove)
        }
    }

    static func scoreMove(_ move: SgMove,
                          on board: SgBoard,
                          context: SgSearchContext?,
                          depth: Int,
                          ttMove: SgMove?) -> Int {
        // 1. TT-move 最优先
        if let tt = ttMove, tt == move {
            return 1_000_000
        }
        // 2. 吃子：MVV-LVA
        if let target = board.piece(at: move.to) {
            let victim = SgEvaluator.materialValue(of: target.type)
            let attacker = SgEvaluator.materialValue(of: board.piece(at: move.from)?.type ?? .pawn)
            return 100_000 + victim * 10 - attacker
        }
        // 3. 杀手走法
        if let ctx = context, ctx.isKiller(move, depth: depth) {
            return 50_000
        }
        // 4. 历史启发
        if let ctx = context {
            return ctx.historyScore(move)
        }
        return 0
    }

    // MARK: - 快照（替代 apply/undo，因为 SgGameFlow.play 会改变 aliveNations/annexed）

    /// 由于 SgGameFlow.play 会修改 aliveNations/annexed（apply/undo 不处理这些），
    /// 搜索中需要完整快照-恢复。
    struct Snapshot {
        let pieces: [SgPos: SgPiece]
        let sideToMove: SgNation
        let aliveNations: Set<SgNation>
        let annexed: [SgNation: SgNation]

        static func take(from board: SgBoard) -> Snapshot {
            return Snapshot(pieces: board.pieces,
                            sideToMove: board.sideToMove,
                            aliveNations: board.aliveNations,
                            annexed: board.annexed)
        }

        static func restore(_ snap: Snapshot, to board: SgBoard) {
            board.restoreSnapshot(pieces: snap.pieces,
                                  sideToMove: snap.sideToMove,
                                  aliveNations: snap.aliveNations,
                                  annexed: snap.annexed)
        }
    }
}
