//
//  SgSearch.swift
//  sanguochese
//
//  三国象棋 · 搜索引擎 (P5-2 / P5-3 / P5-4 / P5-5)
//
//  分阶段混合策略：
//    - 三国阶段（3 方存活）：Paranoid search
//      假设所有对手联合对付当前搜索方，可复用 αβ 框架。
//    - 两方阶段（灭国后）：标准 αβ。
//    - 吞并突变（P5-4）：在 play 之后若存活方数变化，重新评估并降维。
//
//  Paranoid 的核心技巧：把"我方最大化"映射成零和博弈——
//    评估值 = myScore - max(opponentScores)
//  对手方走子时，等价于在"最小化 myScore - max(opponentScores)"。
//  由于 max(opponentScores) 对手方各自只能影响自己的分数，
//  实际实现用"当前应走方视角的相对分"做 αβ，回合切换时取反。
//

import Foundation

/// 难度档位（P5-5）
public enum SgDifficulty: Int, CaseIterable {
    case easy    = 0   // 深度 2 + 30% 随机
    case normal  = 1   // 深度 3 + 10% 随机
    case hard    = 2   // 深度 4
    case expert  = 3   // 深度 5

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

        return searchRoot(for: side, on: board, depth: difficulty.depth, moves: moves)
    }

    // MARK: - 根节点搜索

    /// 根节点：枚举所有合法走法，取最优。
    /// 三国阶段用 Paranoid（相对分 αβ），两方阶段用标准 αβ。
    static func searchRoot(for side: SgNation,
                           on board: SgBoard,
                           depth: Int,
                           moves: [SgMove]) -> SgSearchResult {
        let isThreeNation = board.aliveNations.count >= 3
        // 根节点对走法排序：优先吃子，提升 αβ 剪枝
        let ordered = orderMoves(moves, on: board)

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
                // Paranoid：对手方最小化"side 的相对分"
                score = -paranoid(board: board,
                                  rootSide: side,
                                  depth: depth - 1,
                                  alpha: -beta,
                                  beta: -alpha,
                                  pv: &childPV)
            } else {
                score = -alphabeta(board: board,
                                   rootSide: side,
                                   depth: depth - 1,
                                   alpha: -beta,
                                   beta: -alpha,
                                   pv: &childPV)
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
                         pv: inout [SgMove]) -> Int {
        // 终局
        if case .gameOver(let winner) = SgGameFlow.result(of: board) {
            return terminalScore(for: rootSide, winner: winner)
        }
        if depth <= 0 {
            return relativeScore(for: rootSide, on: board)
        }

        let side = board.sideToMove
        let moves = SgLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            // 当前应走方无子可走：会被吞并，对 rootSide 的影响由后续结算决定。
            // 简化：给一个大的负分（若 side == rootSide）或正分（若 side 是对手）。
            return side == rootSide ? -SgEvaluator.kingValue : SgEvaluator.kingValue
        }

        let ordered = orderMoves(moves, on: board)
        var a = alpha
        var b = beta
        var best = Int.min + 1

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
                                  pv: &childPV)
            }
            Snapshot.restore(snapshot, to: board)

            if score > best {
                best = score
                pv = [move] + childPV
            }
            if best > a { a = best }
            if a >= b { break }  // β cutoff
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
                          pv: inout [SgMove]) -> Int {
        if case .gameOver(let winner) = SgGameFlow.result(of: board) {
            return terminalScore(for: rootSide, winner: winner)
        }
        if depth <= 0 {
            return relativeScore(for: rootSide, on: board)
        }

        let side = board.sideToMove
        let moves = SgLegality.legalMoves(for: side, on: board)
        if moves.isEmpty {
            return side == rootSide ? -SgEvaluator.kingValue : SgEvaluator.kingValue
        }

        let ordered = orderMoves(moves, on: board)
        var a = alpha
        var b = beta
        var best = Int.min + 1

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
                                   pv: &childPV)
            }
            Snapshot.restore(snapshot, to: board)

            if score > best {
                best = score
                pv = [move] + childPV
            }
            if best > a { a = best }
            if a >= b { break }
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

    // MARK: - 走法排序（吃子优先，提升剪枝）

    static func orderMoves(_ moves: [SgMove], on board: SgBoard) -> [SgMove] {
        return moves.sorted { a, b in
            scoreMove(a, on: board) > scoreMove(b, on: board)
        }
    }

    static func scoreMove(_ move: SgMove, on board: SgBoard) -> Int {
        guard let target = board.piece(at: move.to) else { return 0 }
        // 吃子：按被吃子价值
        return SgEvaluator.materialValue(of: target.type)
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
