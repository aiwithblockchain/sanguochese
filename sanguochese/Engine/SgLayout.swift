//
//  SgLayout.swift
//  sanguochese
//
//  三国象棋 - 初始布局
//
//  每方 16 子，阵形与传统象棋半盘完全一致：
//    rank 1: 车 马 象 士 帅 士 象 马 车   (file 1..9)
//    rank 3: . 炮 . . . . . 炮 .
//    rank 4: 兵 . 兵 . 兵 . 兵 . 兵
//

import Foundation

public enum SgLayout {

    /// 生成三方初始棋盘
    public static func initialBoard() -> SgBoard {
        let board = SgBoard()
        for nation in SgNation.allCases {
            place(for: nation, on: board)
        }
        board.sideToMove = .wei
        return board
    }

    /// 在棋盘上摆放一方的 16 枚棋子（传统阵形）
    private static func place(for nation: SgNation, on board: SgBoard) {
        // rank 1: 车马象士帅士象马车
        let backRow: [SgPieceType] = [.rook, .knight, .bishop, .advisor, .king,
                                      .advisor, .bishop, .knight, .rook]
        for (idx, type) in backRow.enumerated() {
            let file = idx + 1
            board.pieces[SgPos(nation: nation, file: file, rank: 1)] = SgPiece(type: type, nation: nation)
        }
        // rank 3: 炮在 file 2 和 file 8
        board.pieces[SgPos(nation: nation, file: 2, rank: 3)] = SgPiece(type: .cannon, nation: nation)
        board.pieces[SgPos(nation: nation, file: 8, rank: 3)] = SgPiece(type: .cannon, nation: nation)
        // rank 4: 兵在 file 1,3,5,7,9
        for file in [1, 3, 5, 7, 9] {
            board.pieces[SgPos(nation: nation, file: file, rank: 4)] = SgPiece(type: .pawn, nation: nation)
        }
    }
}
