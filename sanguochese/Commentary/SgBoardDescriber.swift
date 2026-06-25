//
//  SgBoardDescriber.swift
//  sanguochese
//
//  三国象棋 · 局面描述生成 (P6-2)
//
//  把 SgBoard 序列化为自然语言描述，喂给 LLM 做解说。
//  包含：
//    - 三方剩余子力对比
//    - 刚走的步及其战术意图（是否吃子、是否过河、是否照面）
//    - 主帅安全状态
//  纯文本输出，不依赖 LLM。
//

import Foundation

public enum SgBoardDescriber {

    /// 生成完整局面描述文本。
    /// - Parameters:
    ///   - board: 走子后的局面
    ///   - lastMove: 刚执行的走法（nil = 开局）
    public static func describe(board: SgBoard, lastMove: SgMove?) -> String {
        var lines: [String] = []
        lines.append("【局面】")
        lines.append("存活方：\(aliveText(board))")
        lines.append("当前轮到：\(board.sideToMove.displayName)方")
        lines.append(materialSection(board))
        if let move = lastMove {
            lines.append(moveSection(move, on: board))
        }
        lines.append(kingSafetySection(board))
        return lines.joined(separator: "\n")
    }

    // MARK: - 存活方

    static func aliveText(_ board: SgBoard) -> String {
        let alive = SgNation.allCases.filter { board.isAlive($0) }
            .map { $0.displayName }.joined(separator: "、")
        var text = alive
        if !board.annexed.isEmpty {
            let rels = board.annexed.map { "\($0.key.displayName)→\($0.value.displayName)" }
                .joined(separator: "、")
            text += "（已灭国：\(rels)）"
        }
        return text
    }

    // MARK: - 子力对比

    static func materialSection(_ board: SgBoard) -> String {
        var parts: [String] = ["【子力】"]
        for nation in SgNation.allCases where board.isAlive(nation) {
            let total = board.positions(of: nation).reduce(0) { sum, pos in
                guard let p = board.piece(at: pos) else { return sum }
                return sum + SgEvaluator.materialValue(of: p.type)
            }
            let counts = pieceCounts(for: nation, on: board)
            parts.append("\(nation.displayName)方：总分\(total)，\(counts)")
        }
        return parts.joined(separator: "\n")
    }

    static func pieceCounts(for nation: SgNation, on board: SgBoard) -> String {
        var counts: [SgPieceType: Int] = [:]
        for (_, p) in board.pieces where p.nation == nation {
            counts[p.type, default: 0] += 1
        }
        // 按价值降序列出
        let order: [SgPieceType] = [.king, .rook, .cannon, .knight, .bishop, .advisor, .pawn]
        return order.compactMap { type in
            guard let n = counts[type] else { return nil }
            return "\(type.displayName)\(n)"
        }.joined(separator: " ")
    }

    // MARK: - 走法描述

    static func moveSection(_ move: SgMove, on board: SgBoard) -> String {
        // 注意：调用时 board 已 apply(move)，故 move.from 已空、move.to 是走子方棋子。
        let mover = board.piece(at: move.to)?.nation ?? .wei
        let pieceType = board.piece(at: move.to)?.type ?? .pawn
        var parts: [String] = ["【刚走】"]
        parts.append("\(mover.displayName)方\(pieceType.displayName)：\(move.from.description)→\(move.to.description)")
        var tags: [String] = []
        if move.crossesBorder { tags.append("过国界") }
        // 吃子：无法从 board 直接判断（被吃子已不在），由调用方在 play 前传入更准确；
        // 这里用"终点在走子前是否有子"近似——若终点与走子方同国且非空，则可能是换位（罕见），简化为：
        // 若终点原本有他方棋子，由 describer 调用方补充。此处给出保守判断。
        if move.to.nation != mover { tags.append("深入敌境") }
        if SgLegality.isKingExposed(side: mover, on: board) {
            tags.append("主帅照面")
        }
        if !tags.isEmpty {
            parts.append("标签：\(tags.joined(separator: "、"))")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - 主帅安全

    static func kingSafetySection(_ board: SgBoard) -> String {
        var parts: [String] = ["【主帅安全】"]
        for nation in SgNation.allCases where board.isAlive(nation) {
            let exposed = SgLegality.isKingExposed(side: nation, on: board)
            let status = exposed ? "被照面（危险）" : "安全"
            parts.append("\(nation.displayName)方主帅：\(status)")
        }
        return parts.joined(separator: "\n")
    }
}
