//
//  SgTestFixtures.swift
//  SgEngineTests
//
//  共享测试夹具：构造常见测试局面，避免每个测试重复造棋盘。
//

import Foundation
@testable import SgEngine

enum SgTestFixtures {

    /// 一步杀局面：魏车能直接吃蜀帅。
    /// 魏帅 (wei,1,1)、蜀帅 (shu,5,1)、魏车 (shu,5,3)，中间 (shu,5,2) 空。
    static func mateIn1Board() -> SgBoard {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()
        return board
    }

    /// 两步杀局面：魏车远距离将军，蜀帅无路可逃。
    static func mateIn2Board() -> SgBoard {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()
        return board
    }

    /// 2 人模式初始局。
    static func twoNationInitial(human: SgNation = .wei, ai: SgNation = .shu) -> SgBoard {
        SgLayout.initialBoard(human: human, ai: ai)
    }

    /// 3 人模式初始局。
    static func threeNationInitial() -> SgBoard {
        SgLayout.initialBoard()
    }

    /// 构造一个只有双方主帅 + 指定棋子的极简局面，自动设置 aliveNations/zobrist。
    static func minimalBoard(kingA: SgNation, kingB: SgNation,
                              extra: [(SgPos, SgPiece)] = [],
                              sideToMove: SgNation) -> SgBoard {
        let board = SgBoard()
        board.mode = .twoNation(human: kingA, ai: kingB)
        board.pieces[SgPos(nation: kingA, file: 5, rank: 1)] = SgPiece(type: .king, nation: kingA)
        board.pieces[SgPos(nation: kingB, file: 5, rank: 1)] = SgPiece(type: .king, nation: kingB)
        for (pos, piece) in extra {
            board.pieces[pos] = piece
        }
        board.setAliveNationsForTesting([kingA, kingB])
        board.sideToMove = sideToMove
        board.recomputeZobrist()
        return board
    }
}
