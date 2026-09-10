// Tests/KokoroTextChunkingTests/KokoroTextChunkingTests.swift
// KokoroVoice
//
// Unit tests for KokoroTextChunking

import XCTest
@testable import KokoroVoiceShared

final class KokoroTextChunkingTests: XCTestCase {

    // MARK: - Bisect

    func testBisectPrefersSentenceBoundaryNearMiddle() {
        let text = "First sentence here. Second sentence there. Third sentence closes."
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "First sentence here. Second sentence there.")
        XCTAssertEqual(tail, "Third sentence closes.")
    }

    func testBisectKeepsTerminatorRunsWithTheirSentence() {
        let text = "Is this really working?! It seems so."
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "Is this really working?!")
        XCTAssertEqual(tail, "It seems so.")
    }

    func testBisectFallsBackToClausePunctuation() {
        let text = "one two three four, five six seven eight"
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "one two three four,")
        XCTAssertEqual(tail, "five six seven eight")
    }

    func testBisectSplitsAtDashes() {
        let text = "the first stretch of words—the second stretch"
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "the first stretch of words")
        XCTAssertEqual(tail, "—the second stretch")
    }

    func testBisectFallsBackToWordGap() {
        let text = "alpha beta gamma delta epsilon"
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "alpha beta gamma")
        XCTAssertEqual(tail, "delta epsilon")
    }

    func testBisectHardCutsSingleWord() {
        let text = "abcdefgh"
        let (head, tail) = KokoroTextChunking.bisect(text)!
        XCTAssertEqual(head, "abcd")
        XCTAssertEqual(tail, "efgh")
    }

    func testBisectRefusesUnsplittableText() {
        XCTAssertNil(KokoroTextChunking.bisect("a"))
        XCTAssertNil(KokoroTextChunking.bisect(""))
        XCTAssertNil(KokoroTextChunking.bisect("   a   "))
    }

    func testBisectIgnoresLeadingAndTrailingPadding() {
        let leading = KokoroTextChunking.bisect("        abcdef")
        XCTAssertNotNil(leading)
        XCTAssertEqual(leading?.0, "abc")
        XCTAssertEqual(leading?.1, "def")

        let trailing = KokoroTextChunking.bisect("abcdef        ")
        XCTAssertNotNil(trailing)
        XCTAssertEqual(trailing?.0, "abc")
        XCTAssertEqual(trailing?.1, "def")
    }

    func testBisectNeverProducesEmptyHalves() {
        for text in ["ab", "a b", ". a", "word.", "  two  words  "] {
            if let (head, tail) = KokoroTextChunking.bisect(text) {
                XCTAssertFalse(head.isEmpty, "empty head for \(text)")
                XCTAssertFalse(tail.isEmpty, "empty tail for \(text)")
            }
        }
    }

    // MARK: - Synthesize (buffered)

    private struct FakeLimit: Error {}

    /// A fake engine that refuses pieces over `limit` characters and encodes
    /// each accepted piece's scalars as audio, so splices can be verified.
    private final class FakeEngine {
        let limit: Int
        var accepted: [String] = []

        init(limit: Int) { self.limit = limit }

        func synthesize(_ text: String) async throws -> [Float] {
            try await KokoroTextChunking.synthesize(
                text: text,
                isTokenLimit: { $0 is FakeLimit },
                generate: { piece in
                    guard piece.count <= self.limit else { throw FakeLimit() }
                    self.accepted.append(piece)
                    return piece.unicodeScalars.map { Float($0.value) }
                }
            )
        }
    }

    func testTextWithinLimitPassesThroughUnsplit() async throws {
        let engine = FakeEngine(limit: 100)
        let audio = try await engine.synthesize("short enough")
        XCTAssertEqual(engine.accepted, ["short enough"])
        XCTAssertEqual(audio.count, "short enough".unicodeScalars.count)
    }

    func testLongTextIsSplitUntilEveryPieceFitsAndAudioSplicesInOrder() async throws {
        let text = "The first sentence sets things up. The second sentence carries on, with a clause. The third one closes it out."
        let engine = FakeEngine(limit: 40)
        let audio = try await engine.synthesize(text)

        let pieces = engine.accepted
        XCTAssertGreaterThan(pieces.count, 1)
        for piece in pieces {
            XCTAssertLessThanOrEqual(piece.count, 40, "piece over limit: \(piece)")
        }
        // Pieces reassemble the original text (whitespace at splits is trimmed).
        let reassembled = pieces.joined(separator: " ")
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertEqual(reassembled, normalized)
        // Audio is the concatenation of each accepted piece's rendering, in order.
        let expected = pieces.flatMap { $0.unicodeScalars.map { Float($0.value) } }
        XCTAssertEqual(audio, expected)
    }

    func testRefusalOnUnsplittableTextRethrows() async {
        let engine = FakeEngine(limit: 0)
        do {
            _ = try await engine.synthesize("a")
            XCTFail("an unsplittable refusal must rethrow")
        } catch {
            XCTAssertTrue(error is FakeLimit, "unexpected error: \(error)")
        }
    }

    func testOtherErrorsPropagateWithoutSplitting() async {
        struct Unrelated: Error {}
        var attempts = 0
        do {
            _ = try await KokoroTextChunking.synthesize(
                text: "some words that could be split",
                isTokenLimit: { _ in false },
                generate: { _ in
                    attempts += 1
                    throw Unrelated()
                }
            )
            XCTFail("a non-limit error must propagate")
        } catch {
            XCTAssertTrue(error is Unrelated, "unexpected error: \(error)")
        }
        XCTAssertEqual(attempts, 1, "a non-limit error must not trigger splitting")
    }

    func testPaddedOversizedTextStillSplits() async throws {
        let engine = FakeEngine(limit: 3)
        for text in ["        abcdef", "abcdef        "] {
            engine.accepted = []
            _ = try await engine.synthesize(text)
            XCTAssertEqual(engine.accepted, ["abc", "def"], "padding must not block splitting for \(text)")
        }
    }

    func testCancellationStopsBetweenPieces() async {
        let text = String(repeating: "hello ", count: 128)
        var accepted = 0
        do {
            _ = try await KokoroTextChunking.synthesize(
                text: text,
                isTokenLimit: { $0 is FakeLimit },
                generate: { piece in
                    guard piece.count <= 32 else { throw FakeLimit() }
                    accepted += 1
                    if accepted == 1 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    return [1]
                }
            )
            XCTFail("cancellation must stop synthesis")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error: \(error)")
        }
        XCTAssertEqual(accepted, 1, "no further pieces may render after cancellation")
    }

    func testPathologicallyLongSingleRunTerminates() async throws {
        let text = String(repeating: "ab", count: 2000)
        let engine = FakeEngine(limit: 100)
        let audio = try await engine.synthesize(text)
        for piece in engine.accepted {
            XCTAssertLessThanOrEqual(piece.count, 100)
        }
        XCTAssertEqual(engine.accepted.joined(), text)
        XCTAssertEqual(audio.count, text.count)
    }

    // MARK: - Synthesize (per-piece streaming)

    func testEachPieceReachesConsumerBeforeNextIsGenerated() async throws {
        // 22 characters with a 12-character limit: one bisect yields
        // "alpha beta" and "gamma delta", both accepted.
        var events: [String] = []
        let completed = try await KokoroTextChunking.synthesize(
            text: "alpha beta gamma delta",
            isTokenLimit: { $0 is FakeLimit },
            generate: { piece in
                guard piece.count <= 12 else { throw FakeLimit() }
                events.append("generate(\(piece))")
                return piece.unicodeScalars.map { Float($0.value) }
            },
            consume: { audio in
                events.append("consume(\(audio.count))")
                return true
            }
        )
        XCTAssertTrue(completed)
        XCTAssertEqual(events, [
            "generate(alpha beta)",
            "consume(10)",
            "generate(gamma delta)",
            "consume(11)",
        ], "each accepted piece must be consumed before the next is generated")
    }

    func testConsumerReturningFalseStopsFurtherGeneration() async throws {
        var generated: [String] = []
        let completed = try await KokoroTextChunking.synthesize(
            text: "alpha beta gamma delta",
            isTokenLimit: { $0 is FakeLimit },
            generate: { piece in
                guard piece.count <= 12 else { throw FakeLimit() }
                generated.append(piece)
                return [1]
            },
            consume: { _ in false }
        )
        XCTAssertFalse(completed, "a stopped traversal must not report completion")
        XCTAssertEqual(generated, ["alpha beta"], "a stopped consumer must prevent further generation")
    }

    func testConsumerErrorPropagatesWithoutFurtherGeneration() async {
        struct SinkFailure: Error {}
        var generated = 0
        do {
            _ = try await KokoroTextChunking.synthesize(
                text: "alpha beta gamma delta",
                isTokenLimit: { $0 is FakeLimit },
                generate: { piece in
                    guard piece.count <= 12 else { throw FakeLimit() }
                    generated += 1
                    return [1]
                },
                consume: { _ in throw SinkFailure() }
            )
            XCTFail("a consumer error must propagate")
        } catch {
            XCTAssertTrue(error is SinkFailure, "unexpected error: \(error)")
        }
        XCTAssertEqual(generated, 1, "a failed consumer must prevent further generation")
    }
}
