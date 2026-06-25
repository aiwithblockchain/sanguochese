//
//  TnLayout.swift
//  sanguochese
//
//  2 人标准中国象棋 · 初始布局
//
//  红方在下（rank 0..4），黑方在上（rank 5..9）。
//  rank 0: 车马相仕帅仕相马车（红）
//  rank 2: 炮在 file 1、7
//  rank 3: 兵在 file 0,2,4,6,8
//  黑方对称（rank 9/7/6）。
//

import Foundation

public enum TnLayout {

    /// 生成标准初始棋盘，红先。
    public static func initialBoard() -> TnBoard {
        let board = TnBoard()
        place(.red, on: board)
        place(.black, on: board)
        board.recomputeZobrist()
        return board
    }

    private static func place(_ color: TnColor, on board: TnBoard) {
        // rank 0（红）/ rank 9（黑）：车马相仕帅仕相马车
        let backRank = color == .red ? 0 : 9
        let backRow: [TnPieceType] = [.rook, .knight, .bishop, .advisor, .king,
                                      .advisor, .bishop, .knight, .rook]
        for (i, t) in backRow.enumerated() {
            board.pieces[TnPos(file: i, rank: backRank)] = TnPiece(type: t, color: color)
        }
        // 炮：file 1、7，rank 2（红）/ rank 7（黑）
        let cannonRank = color == .red ? 2 : 7
        for f in [1, 7] {
            board.pieces[TnPos(file: f, rank: cannonRank)] = TnPiece(type: .cannon, color: color)
        }
        // 兵：file 0,2,4,6,8，rank 3（红）/ rank 6（黑）
        let pawnRank = color == .red ? 3 : 6
        for f in [0, 2, 4, 6, 8] {
            board.pieces[TnPos(file: f, rank: pawnRank)] = TnPiece(type: .pawn, color: color)
        }
    }
}
