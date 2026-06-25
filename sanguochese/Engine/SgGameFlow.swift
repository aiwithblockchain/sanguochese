//
//  SgGameFlow.swift
//  sanguochese
//
//  三国象棋 · 灭国吞并状态机 (P4)
//
//  负责走子后的结算：
//    P4-1 吃帅灭国判定
//    P4-2 棋子收编与改色（由 SgBoard.annex 完成）
//    P4-3 收编兵卒方向重定义（由 SgMoveGen.pawnMoves 在两方阶段处理）
//    P4-4 无子可走判负
//    P4-5 三国阶段消极判负（无过河棋清空）
//    P4-7 终局判定（最后存活方获胜）
//
//  P4-6 两方阶段和棋暂留接口，细则待后续细化。
//

import Foundation

/// 一局游戏的整体结果
public enum SgGameResult: Equatable {
    case ongoing
    case gameOver(winner: SgNation)
}

/// 单步走法导致的结算事件（供 UI 做提示/动画）
public enum SgMoveOutcome: Equatable {
    case ongoing
    /// 吃帅灭国：败方棋子归胜方
    case annexed(defeated: SgNation, victor: SgNation)
    /// 消极判负：败方棋子清空（不归任何方）
    case cleared(defeated: SgNation)
    /// 无子可走判负：败方棋子归致因方
    case noMovesDefeated(defeated: SgNation, victor: SgNation)
    /// 终局：最后存活方获胜
    case gameOver(winner: SgNation)
}

public enum SgGameFlow {

    /// 执行一步走法并完成全部结算（含回合轮转）。
    /// 调用后 board.sideToMove 已指向下一个应走方。
    @discardableResult
    public static func play(_ move: SgMove, on board: SgBoard) -> SgMoveOutcome {
        let mover = board.sideToMove
        let captured = board.apply(move)

        // P4-1 / P4-2：吃到主帅 → 触发吞并
        if let cap = captured, cap.type == .king {
            let defeated = cap.nation
            // 两方模式：吃帅即终局，不吞并
            if board.mode.isTwoNation {
                board.aliveNations.remove(defeated)
                board.zobrist ^= SgZobrist.aliveKeys[defeated.rawValue]
                log("🏆 两方终局: \(mover.displayName) 吃掉 \(defeated.displayName) 主帅")
                return .gameOver(winner: mover)
            }
            log("🎯 吃帅灭国: \(mover.displayName) 吃掉 \(defeated.displayName) 主帅，触发吞并")
            board.annex(defeated: defeated, by: mover)
            if board.aliveNations.count == 1 {
                log("🏆 终局: \(mover.displayName) 一统天下")
                return .gameOver(winner: mover)
            }
            advanceTurn(on: board)
            // 吞并后仍需检查新应走方是否无子可走（可能被吞并后的局面困毙）
            return merge(.annexed(defeated: defeated, victor: mover),
                         settleCurrentSide(on: board, causedBy: mover))
        }

        advanceTurn(on: board)
        return settleCurrentSide(on: board, causedBy: mover)
    }

    /// 当前整体游戏结果
    public static func result(of board: SgBoard) -> SgGameResult {
        // 两方模式：任一方主帅不在 → 对方胜
        if board.mode.isTwoNation {
            for nation in board.aliveNations {
                if board.kingPos(of: nation) == nil {
                    let winner = board.aliveNations.first(where: { $0 != nation }) ?? nation
                    return .gameOver(winner: winner)
                }
            }
            return .ongoing
        }
        if board.aliveNations.count == 1, let w = board.aliveNations.first {
            return .gameOver(winner: w)
        }
        return .ongoing
    }

    // MARK: - 回合轮转

    /// 推进到下一个存活方
    private static func advanceTurn(on board: SgBoard) {
        var s = board.sideToMove.next()
        var guardCount = 0
        while !board.isAlive(s) {
            s = s.next()
            guardCount += 1
            if guardCount > 3 { return }  // 安全保护
        }
        board.setSideToMove(s)
    }

    // MARK: - 结算当前应走方

    /// 检查当前 sideToMove 是否触发消极判负 / 无子可走判负。
    /// 若触发并导致局面变化，递归结算下一个应走方。
    private static func settleCurrentSide(on board: SgBoard, causedBy mover: SgNation) -> SgMoveOutcome {
        let side = board.sideToMove
        guard board.isAlive(side) else { return .ongoing }

        // P4-5 三国阶段消极判负：无过河棋且他方已有过河棋
        if board.aliveNations.count == 3,
           !hasCrossedPieces(side, on: board),
           allOtherAliveSidesHaveCrossed(side, on: board) {
            board.clearAll(of: side)
            if board.aliveNations.count == 1, let w = board.aliveNations.first {
                return .gameOver(winner: w)
            }
            advanceTurn(on: board)
            return merge(.cleared(defeated: side),
                         settleCurrentSide(on: board, causedBy: mover))
        }

        // P4-4 无子可走判负
        if SgLegality.hasNoLegalMoves(side: side, on: board) {
            // 两方模式：无子可走即终局，不吞并
            if board.mode.isTwoNation {
                let victor = board.aliveNations.first(where: { $0 != side }) ?? mover
                board.aliveNations.remove(side)
                board.zobrist ^= SgZobrist.aliveKeys[side.rawValue]
                log("🏆 两方终局: \(side.displayName) 无子可走，\(victor.displayName) 胜")
                return .gameOver(winner: victor)
            }
            // 致因方：默认归当前进攻方（mover）；若 mover 已亡则取剩余存活方
            let victor = board.isAlive(mover) ? mover : board.aliveNations.first(where: { $0 != side }) ?? mover
            board.annex(defeated: side, by: victor)
            if board.aliveNations.count == 1 {
                return .gameOver(winner: victor)
            }
            advanceTurn(on: board)
            return merge(.noMovesDefeated(defeated: side, victor: victor),
                         settleCurrentSide(on: board, causedBy: mover))
        }

        return .ongoing
    }

    // MARK: - 过河棋判定

    /// 某方是否有过河棋（棋子位于非己方领土）
    public static func hasCrossedPieces(_ side: SgNation, on board: SgBoard) -> Bool {
        for (pos, p) in board.pieces where p.nation == side {
            if pos.nation != side { return true }
        }
        return false
    }

    /// 除 side 外，所有其他存活方是否都至少有一个过河棋。
    private static func allOtherAliveSidesHaveCrossed(_ side: SgNation, on board: SgBoard) -> Bool {
        for other in board.aliveNations where other != side {
            if !hasCrossedPieces(other, on: board) { return false }
        }
        return true
    }

    // MARK: - 事件合并

    /// 把后续结算事件合并到主事件上：终局优先，否则保留主事件。
    private static func merge(_ primary: SgMoveOutcome, _ follow: SgMoveOutcome) -> SgMoveOutcome {
        if case .gameOver = follow { return follow }
        if case .gameOver = primary { return primary }
        // 若后续有新的灭国事件且主事件只是 ongoing，返回后续
        if case .ongoing = primary { return follow }
        return primary
    }

    // MARK: - 调试日志

    private static func log(_ message: String) {
        #if DEBUG
        print("[SgGameFlow] \(message)")
        #endif
    }
}
