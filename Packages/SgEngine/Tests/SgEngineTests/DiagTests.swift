// Quick diagnostic: print legal moves and search scores for the capture-to-escape position
import XCTest
@testable import SgEngine

final class DiagTests: XCTestCase {
    func testDiagCaptureToEscape() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        let legal = SgLegality.legalMoves(for: .shu, on: board)
        print("DIAG legal moves for shu: \(legal.map { $0.description })")
        for m in legal {
            let cap = board.apply(m)
            let inChk = SgLegality.isInCheck(side: .shu, on: board)
            let rel = SgEvaluator.evaluate(board).relative(for: .shu, alive: [.wei, .shu])
            board.undo(m, captured: cap)
            print("DIAG move \(m.description): inCheckAfter=\(inChk) relativeEval=\(rel) captured=\(cap?.type.rawValue ?? "nil")")
        }
        let result = SgSearch.chooseMove(for: .shu, on: board, difficulty: .hard)
        print("DIAG search chose: \(result.move?.description ?? "nil") score=\(result.score)")
    }
}
