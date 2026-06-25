//
//  TnGameFlow.swift
//  sanguochese
//
//  2 人标准中国象棋 · 游戏流程 / 终局判定
//
//  规则：
//    - 红先。
//    - 判负：吃帅（被吃方负）/ 无子可走（困毙/将死，该方负）。
//    - 飞将照面由 TnLegality 过滤（走法生成层已排除照面走法）。
//    - 暂不实现：和棋、重复局面、消极判负（后续可加）。
//
//  与 SgGameFlow 完全独立（无吞并/灭国概念）。
//
//  注意：本类型供 UI 走子用，使用 board.make()（含回合轮转 + 增量 Zobrist）。
//  搜索层直接用 board.make/unmake，不走 TnGameFlow。
//

import Foundation

/// 一局游戏的整体结果
public enum TnGameResult: Equatable {
    case ongoing
    case gameOver(winner: TnColor)
}

/// 单步走法导致的结算事件（供 UI 做提示/动画）
public enum TnMoveOutcome: Equatable {
    case ongoing
    /// 吃帅：胜方
    case kingCaptured(winner: TnColor)
    /// 无子可走（困毙/将死）：胜方
    case noMoves(winner: TnColor)
}

public enum TnGameFlow {

    /// 执行一步走法并完成全部结算（含回合轮转）。
    /// 调用后 board.sideToMove 已指向对方（若未终局）。
    /// 使用 board.make() —— 自动维护增量 Zobrist。
    @discardableResult
    public static func play(_ move: TnMove, on board: TnBoard) -> TnMoveOutcome {
        let mover = board.sideToMove
        let captured = board.piece(at: move.to)

        // 走子 + 回合轮转 + Zobrist 更新（make 内部完成）
        _ = board.make(move)

        // 吃帅 → 终局
        if let cap = captured, cap.type == .king {
            return .kingCaptured(winner: mover)
        }

        // 检查对方是否无子可走
        if TnLegality.hasNoLegalMoves(color: board.sideToMove, on: board) {
            return .noMoves(winner: mover)
        }
        return .ongoing
    }

    /// 当前整体游戏结果
    public static func result(of board: TnBoard) -> TnGameResult {
        // 任一方无帅 → 对方胜
        if board.kingPos(of: .red) == nil {
            return .gameOver(winner: .black)
        }
        if board.kingPos(of: .black) == nil {
            return .gameOver(winner: .red)
        }
        return .ongoing
    }
}
