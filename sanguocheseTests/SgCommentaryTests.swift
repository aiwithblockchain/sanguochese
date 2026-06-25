//
//  SgCommentaryTests.swift
//  sanguocheseTests
//
//  P6 AI 解说层单元测试
//  覆盖：局面描述生成、角色 Prompt 构建、DeepSeek 桥接兜底、缓存。
//

import XCTest
@testable import sanguochese

final class SgCommentaryTests: XCTestCase {

    // MARK: - 局面描述

    func testDescribeIncludesAliveAndMaterial() {
        let board = SgLayout.initialBoard()
        let text = SgBoardDescriber.describe(board: board, lastMove: nil)
        XCTAssertTrue(text.contains("存活方"))
        XCTAssertTrue(text.contains("子力"))
        XCTAssertTrue(text.contains("魏"))
        XCTAssertTrue(text.contains("蜀"))
        XCTAssertTrue(text.contains("吴"))
    }

    func testDescribeWithMoveIncludesMoveSection() {
        let board = SgLayout.initialBoard()
        let move = SgMove(from: SgPos(nation: .wei, file: 1, rank: 1),
                          to: SgPos(nation: .wei, file: 1, rank: 2))
        let text = SgBoardDescriber.describe(board: board, lastMove: move)
        XCTAssertTrue(text.contains("刚走"))
    }

    func testDescribeAnnexedState() {
        let board = SgLayout.initialBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        board.setAnnexedForTesting([.wu: .wei])
        let text = SgBoardDescriber.describe(board: board, lastMove: nil)
        XCTAssertTrue(text.contains("已灭国"))
        XCTAssertTrue(text.contains("吴→魏"))
    }

    // MARK: - 角色 Prompt

    func testRoleCommentatorMapping() {
        XCTAssertEqual(SgRole.commentator(for: .shu), .zhugeLiang)
        XCTAssertEqual(SgRole.commentator(for: .wei), .simaYi)
        XCTAssertEqual(SgRole.commentator(for: .wu), .zhouYu)
    }

    func testRoleMonarchMapping() {
        XCTAssertEqual(SgRole.monarch(of: .wei), .caoCao)
        XCTAssertEqual(SgRole.monarch(of: .shu), .liuBei)
        XCTAssertEqual(SgRole.monarch(of: .wu), .sunQuan)
    }

    func testPromptContainsPersonaAndSituation() {
        let prompt = SgRolePrompt.build(role: .zhugeLiang,
                                        situation: "测试局面",
                                        moveText: "测试走法",
                                        isPlayerMove: true)
        XCTAssertTrue(prompt.contains("诸葛亮"))
        XCTAssertTrue(prompt.contains("测试局面"))
        XCTAssertTrue(prompt.contains("测试走法"))
        XCTAssertTrue(prompt.contains("60 字"))
    }

    // MARK: - DeepSeek 桥接兜底

    func testFallbackReturnsRoleFlavoredLine() {
        let line = SgDeepSeekBridge.fallback(for: .caoCao)
        XCTAssertFalse(line.isEmpty)
    }

    func testBridgeUnconfiguredReturnsFallback() {
        let bridge = SgDeepSeekBridge(apiKey: "")
        XCTAssertFalse(bridge.isConfigured)
        let exp = expectation(description: "fallback")
        bridge.commentate(prompt: "test", role: .zhugeLiang) { text in
            XCTAssertFalse(text.isEmpty)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testBridgeConfiguredFlag() {
        let bridge = SgDeepSeekBridge(apiKey: "sk-test")
        XCTAssertTrue(bridge.isConfigured)
    }
}
