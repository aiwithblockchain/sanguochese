//
//  TnSearch.swift
//  sanguochese
//
//  2 人标准中国象棋 · 搜索引擎
//
//  纯标准 negamax αβ（无 Paranoid）：
//    - αβ + quiescence（吃子延伸，消除 horizon effect）
//    - 置换表（增量 Zobrist）
//    - 迭代加深 + PV 先导排序
//    - 杀手走法 + 历史启发
//    - 走法排序：TT-move → MVV-LVA 吃子 → killer → history
//    - Late Move Reduction（专家档，非 PV 节点）
//
//  2 人模式无吞并，吃帅即终局，全部走 make/unmake（无 Snapshot 分支）。
//
//  评估视角：TnEvaluator.evaluate 返回红方视角标量（正=红优）。
//  negamax 中按 sideToMove 翻转：side==.red ? eval : -eval。
//

import Foundation

/// 难度档位
public enum TnDifficulty: Int, CaseIterable {
    case easy    = 0   // 深度 2 + 30% 随机
    case normal  = 1   // 深度 3 + 10% 随机
    case hard    = 2   // 深度 4
    case expert  = 3   // 深度 5 + 迭代加深 + 置换表 + LMR

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

    /// 是否启用高级优化（置换表/迭代加深/杀手走法/LMR）
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
public struct TnSearchResult {
    public let move: TnMove?
    public let score: Int
    public let principalVariation: [TnMove]

    public init(move: TnMove?, score: Int, principalVariation: [TnMove]) {
        self.move = move
        self.score = score
        self.principalVariation = principalVariation
    }
}

/// 搜索上下文 —— 在一次 chooseMove 调用内共享的优化结构。
/// 单线程使用（后台搜索线程独占），无需加锁。
final class TnSearchContext {
    /// 置换表
    let tt: TnTranspositionTable
    /// 杀手走法：killerMoves[depth] -> (slot0, slot1)
    var killerMoves: [(TnMove?, TnMove?)]
    /// 历史启发：history[fromIndex*90 + toIndex] -> score
    var history: [Int]
    /// 当前搜索的目标深度（用于 killer 槽索引）
    var maxDepth: Int = 0

    init() {
        self.tt = TnTranspositionTable()
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
    func recordKiller(_ move: TnMove, depth: Int) {
        let idx = max(0, min(killerMoves.count - 1, depth))
        let (s0, s1) = killerMoves[idx]
        if s0 == nil || s0! == move {
            killerMoves[idx] = (move, s1)
        } else if s1 == nil || s1! == move {
            killerMoves[idx] = (s0, move)
        } else {
            killerMoves[idx] = (move, s0)
        }
    }

    /// 判断走法是否是某层的杀手走法。
    func isKiller(_ move: TnMove, depth: Int) -> Bool {
        let idx = max(0, min(killerMoves.count - 1, depth))
        let (s0, s1) = killerMoves[idx]
        return s0 == move || s1 == move
    }

    /// 历史走法加分。
    func addHistory(_ move: TnMove, depth: Int) {
        let fi = move.from.linearIndex
        let ti = move.to.linearIndex
        let key = fi * 90 + ti
        history[key] &+= depth * depth
    }

    /// 读取历史分。
    func historyScore(_ move: TnMove) -> Int {
        let fi = move.from.linearIndex
        let ti = move.to.linearIndex
        return history[fi * 90 + ti]
    }
}

public enum TnSearch {

    /// 为 `side` 选定一步走法。
    /// - Parameters:
    ///   - side: 当前应走方（必须与 board.sideToMove 一致）
    ///   - board: 局面（不会被修改）
    ///   - difficulty: 难度
    public static func chooseMove(for side: TnColor,
                                  on board: TnBoard,
                                  difficulty: TnDifficulty = .normal) -> TnSearchResult {
        let moves = TnLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            return TnSearchResult(move: nil, score: 0, principalVariation: [])
        }

        // 随机扰动：以 randomChance 概率直接随机走（模拟"失误"）
        if difficulty.randomChance > 0,
           Double.random(in: 0...1) < difficulty.randomChance {
            let pick = moves.randomElement()!
            return TnSearchResult(move: pick, score: 0, principalVariation: [pick])
        }

        if difficulty.useAdvancedOptimizations {
            return iterativeDeepening(for: side, on: board, maxDepth: difficulty.depth, moves: moves)
        }
        return searchRoot(for: side, on: board, depth: difficulty.depth, moves: moves, context: nil)
    }

    // MARK: - 迭代加深

    /// 从深度 1 递增到 maxDepth，每轮用上一轮的 PV 走法作为排序先导。
    /// 软时限：每轮若超过 1.5s 则停止加深。
    static func iterativeDeepening(for side: TnColor,
                                   on board: TnBoard,
                                   maxDepth: Int,
                                   moves: [TnMove]) -> TnSearchResult {
        let context = TnSearchContext()
        context.maxDepth = maxDepth
        context.reset()

        var lastResult = TnSearchResult(move: moves[0], score: 0, principalVariation: [moves[0]])
        let startTime = Date()

        for depth in 1...maxDepth {
            let result = searchRoot(for: side,
                                    on: board,
                                    depth: depth,
                                    moves: moves,
                                    context: context,
                                    pvHint: lastResult.principalVariation)
            if result.move != nil {
                lastResult = result
            }
            if Date().timeIntervalSince(startTime) > 1.5 {
                break
            }
        }
        return lastResult
    }

    // MARK: - 根节点搜索

    /// 根节点：枚举所有合法走法，取最优。标准 negamax。
    static func searchRoot(for side: TnColor,
                           on board: TnBoard,
                           depth: Int,
                           moves: [TnMove],
                           context: TnSearchContext?,
                           pvHint: [TnMove] = []) -> TnSearchResult {
        var ordered = orderMoves(moves, on: board, context: context, depth: depth)
        if !pvHint.isEmpty {
            let pvFirst = pvHint[0]
            if let idx = ordered.firstIndex(of: pvFirst) {
                ordered.remove(at: idx)
                ordered.insert(pvFirst, at: 0)
            }
        }

        var bestMove: TnMove? = nil
        var bestScore = Int.min + 1
        var bestPV: [TnMove] = []
        var alpha = Int.min + 1
        let beta = Int.max - 1

        for move in ordered {
            var childPV: [TnMove] = []
            let rec = board.make(move)
            let score = -alphabeta(board: board,
                                   depth: depth - 1,
                                   alpha: -beta, beta: -alpha,
                                   pv: &childPV, context: context)
            board.unmake(rec)

            if score > bestScore {
                bestScore = score
                bestMove = move
                bestPV = [move] + childPV
            }
            if bestScore > alpha {
                alpha = bestScore
            }
        }

        if let ctx = context {
            ctx.tt.store(TnTTEntry(key: board.zobrist,
                                   depth: depth,
                                   score: bestScore,
                                   flag: .exact,
                                   bestMove: bestMove))
        }

        return TnSearchResult(move: bestMove, score: bestScore, principalVariation: bestPV)
    }

    // MARK: - αβ 搜索（标准 negamax）
    //
    // score = -search(opponent)。
    // 评估值按 sideToMove 翻转：side==.red ? eval : -eval。
    //
    static func alphabeta(board: TnBoard,
                          depth: Int,
                          alpha: Int,
                          beta: Int,
                          pv: inout [TnMove],
                          context: TnSearchContext?) -> Int {
        // 终局
        if case .gameOver(let winner) = TnGameFlow.result(of: board) {
            // 当前应走方负 → -∞
            return winner == board.sideToMove ? (Int.max - 1) : (Int.min + 1)
        }
        if depth <= 0 {
            return quiescence(board: board, alpha: alpha, beta: beta, context: context)
        }

        // 置换表查询
        let hash = board.zobrist
        let ttMove: TnMove? = context?.tt.probe(hash)?.bestMove
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
        let moves = TnLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            // 将死/困毙：当前方负
            return Int.min + 1
        }

        let ordered = orderMoves(moves, on: board, context: context, depth: depth, ttMove: ttMove)
        var a = alpha
        let b = beta
        var best = Int.min + 1
        var bestMove: TnMove? = nil
        var raisedAlpha = false

        for (i, move) in ordered.enumerated() {
            var childPV: [TnMove] = []
            let rec = board.make(move)

            // Late Move Reduction：非 PV 节点、走法排序靠后、深度足够、非吃子
            var score: Int
            if context != nil, depth >= 3, i >= 3, board.piece(at: move.to) == nil {
                // 试探性降深度
                let reduced = depth - 2
                score = -alphabeta(board: board, depth: reduced,
                                   alpha: -b, beta: -a,
                                   pv: &childPV, context: context)
                // 若降深度后仍能引起 α 提升，用原深度重搜
                if score > a {
                    score = -alphabeta(board: board, depth: depth - 1,
                                       alpha: -b, beta: -a,
                                       pv: &childPV, context: context)
                }
            } else {
                score = -alphabeta(board: board, depth: depth - 1,
                                   alpha: -b, beta: -a,
                                   pv: &childPV, context: context)
            }
            board.unmake(rec)

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
                if let ctx = context {
                    ctx.tt.store(TnTTEntry(key: hash, depth: depth, score: best,
                                            flag: .lowerBound, bestMove: bestMove))
                }
                return best
            }
        }

        if let ctx = context {
            let flag: TnTTFlag = raisedAlpha ? .exact : .upperBound
            ctx.tt.store(TnTTEntry(key: hash, depth: depth, score: best,
                                    flag: flag, bestMove: bestMove))
        }
        return best
    }

    /// 取当前搜索的总深度（保留接口兼容，当前未使用 ply）。
    private static func maxDepth_ply(_ context: TnSearchContext?) -> Int {
        context?.maxDepth ?? 0
    }

    // MARK: - Quiescence 静态搜索
    //
    // 在 depth=0 时不直接返回评估，而是延伸吃子序列，消除 horizon effect。
    // 只延伸吃子走法（含吃帅），避免无限延伸。
    //
    static func quiescence(board: TnBoard,
                           alpha: Int,
                           beta: Int,
                           context: TnSearchContext?) -> Int {
        // 终局
        if case .gameOver(let winner) = TnGameFlow.result(of: board) {
            return winner == board.sideToMove ? (Int.max - 1) : (Int.min + 1)
        }

        // stand-pat：当前局面的静态评估（按 sideToMove 翻转）
        let standPat = evaluateForSideToMove(board)
        var alpha = alpha
        if standPat >= beta { return beta }
        if standPat > alpha { alpha = standPat }

        // 只生成吃子走法
        let side = board.sideToMove
        let captures = TnLegality.legalCaptures(for: side, on: board)
        if captures.isEmpty {
            return alpha
        }

        let ordered = orderMoves(captures, on: board, context: context, depth: 0, ttMove: nil)
        let b = beta

        for move in ordered {
            let rec = board.make(move)
            let score = -quiescence(board: board, alpha: -b, beta: -alpha, context: context)
            board.unmake(rec)

            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // MARK: - 评估

    /// 当前应走方视角的评估分。
    /// TnEvaluator.evaluate 返回红方视角（正=红优），
    /// 当前应走方为黑方时取负。
    static func evaluateForSideToMove(_ board: TnBoard) -> Int {
        let redScore = TnEvaluator.evaluate(board)
        return board.sideToMove == .red ? redScore : -redScore
    }

    // MARK: - 走法排序

    /// 走法排序优先级：
    ///   1. 置换表建议走法（TT-move）最前
    ///   2. 吃子（MVV-LVA：被吃子价值 - 吃子价值/10）
    ///   3. 杀手走法（非吃子）
    ///   4. 历史启发分
    static func orderMoves(_ moves: [TnMove],
                           on board: TnBoard,
                           context: TnSearchContext?,
                           depth: Int,
                           ttMove: TnMove? = nil) -> [TnMove] {
        return moves.sorted { a, b in
            scoreMove(a, on: board, context: context, depth: depth, ttMove: ttMove)
                > scoreMove(b, on: board, context: context, depth: depth, ttMove: ttMove)
        }
    }

    static func scoreMove(_ move: TnMove,
                          on board: TnBoard,
                          context: TnSearchContext?,
                          depth: Int,
                          ttMove: TnMove?) -> Int {
        // 1. TT-move 最优先
        if let tt = ttMove, tt == move {
            return 1_000_000
        }
        // 2. 吃子：MVV-LVA
        if let target = board.piece(at: move.to) {
            let victim = TnEvaluator.materialValue(of: target.type)
            let attacker = TnEvaluator.materialValue(of: board.piece(at: move.from)?.type ?? .pawn)
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
}
