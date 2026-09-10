// Shared/KokoroTextChunking.swift
// KokoroVoice
//
// Kokoro's engine refuses input over its token limit (510 phoneme tokens)
// with `tooManyTokens`, thrown after G2P but before any model work — so a
// refused attempt is cheap. Hosts (macOS speech synthesis, callers of
// KokoroEngine) cannot see phoneme counts from outside, and previously a
// too-long segment surfaced as a failed request the OS reports as a clean,
// silent "finished".
//
// This solves it at the source: try the whole text, and on a token-limit
// refusal bisect it at the most natural boundary near the middle (sentence
// end, then clause punctuation, then word gap, then a hard cut) and recurse.
// Every piece the engine accepts is rendered and handed to the caller's
// consumer in text order before the next piece is generated, so a streaming
// caller can publish audio — and apply backpressure — piece by piece instead
// of holding an entire utterance in memory. A buffered convenience splices
// the pieces into one array for callers that need the whole rendering.
// The engine's own acceptance is the oracle, so no character-budget guessing
// is involved. Successful splits make strict progress; they do not
// necessarily produce balanced halves or the minimum number of pieces.
// Rejected attempts repeat G2P but skip acoustic-model inference.

import Foundation

public enum KokoroTextChunking {

    /// Split `text` into two non-empty trimmed halves at the most natural
    /// boundary nearest the middle. Boundary preference: after a sentence
    /// terminator run, after clause punctuation (`,` `;` `:`, or at a dash),
    /// at a word gap, then a hard character cut. Returns nil when the text
    /// cannot produce two non-empty halves.
    public static func bisect(_ text: String) -> (String, String)? {
        // Trim first so midpoint math and the hard fallback operate on the
        // speakable text — padding must never make a splittable text look
        // unsplittable.
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard chars.count >= 2 else { return nil }
        let mid = chars.count / 2

        var sentence: [Int] = []
        var clause: [Int] = []
        var word: [Int] = []
        for i in 1..<chars.count {
            let previous = chars[i - 1]
            let current = chars[i]
            if current.isWhitespace, !previous.isWhitespace {
                word.append(i)
                if ".!?".contains(previous) {
                    sentence.append(i)
                } else if ",;:".contains(previous) {
                    clause.append(i)
                }
            }
            if current == "—" || current == "–" {
                clause.append(i)
            }
        }

        for candidates in [sentence, clause, word] {
            // Nearest the middle first within the highest-priority boundary
            // class; a natural boundary far from the middle still wins over
            // a balanced cut at a lower tier.
            for index in candidates.sorted(by: { abs($0 - mid) < abs($1 - mid) }) {
                if let halves = halves(chars, at: index) { return halves }
            }
        }
        return halves(chars, at: mid)
    }

    private static func halves(_ chars: [Character], at index: Int) -> (String, String)? {
        guard index > 0, index < chars.count else { return nil }
        let head = String(chars[0..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(chars[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, !tail.isEmpty else { return nil }
        return (head, tail)
    }

    /// Render `text` through `generate`, bisecting on token-limit refusals
    /// until every piece is accepted. Each accepted piece's audio is awaited
    /// through `consume` in text order before the next piece is generated,
    /// so a streaming caller can publish audio piece by piece and its
    /// enqueue backpressure paces generation. Return `false` from `consume`
    /// to stop the traversal (e.g. the request's buffer was reset); the
    /// function then returns `false` without generating further pieces, and
    /// returns `true` only when the whole text was rendered and consumed.
    ///
    /// `isTokenLimit` identifies the engine's refusal; any other error —
    /// from `generate` or `consume` — propagates immediately. A refusal on
    /// text that cannot be split further is rethrown for the caller to
    /// report. Task cancellation is checked before every piece, so a
    /// cancelled request stops after the generation in flight instead of
    /// rendering the rest.
    ///
    /// `isolation` defaults to the caller's isolation (SE-0420), so an
    /// actor like `KokoroEngine` can pass closures over its protected state
    /// and they run on that actor rather than crossing an isolation
    /// boundary.
    @discardableResult
    public static func synthesize(
        text: String,
        isolation: isolated (any Actor)? = #isolation,
        isTokenLimit: (any Error) -> Bool,
        generate: (String) async throws -> [Float],
        consume: ([Float]) async throws -> Bool
    ) async throws -> Bool {
        try Task.checkCancellation()
        let audio: [Float]
        do {
            audio = try await generate(text)
        } catch let error where isTokenLimit(error) {
            guard let (head, tail) = bisect(text) else { throw error }
            guard try await synthesize(
                text: head,
                isolation: isolation,
                isTokenLimit: isTokenLimit,
                generate: generate,
                consume: consume
            ) else { return false }
            return try await synthesize(
                text: tail,
                isolation: isolation,
                isTokenLimit: isTokenLimit,
                generate: generate,
                consume: consume
            )
        }
        return try await consume(audio)
    }

    /// Buffered convenience over the per-piece traversal: renders every
    /// piece and returns the audio spliced in order, accumulated into a
    /// single array. Use the `consume:` variant when audio can be published
    /// progressively.
    public static func synthesize(
        text: String,
        isolation: isolated (any Actor)? = #isolation,
        isTokenLimit: (any Error) -> Bool,
        generate: (String) async throws -> [Float]
    ) async throws -> [Float] {
        var spliced: [Float] = []
        _ = try await synthesize(
            text: text,
            isolation: isolation,
            isTokenLimit: isTokenLimit,
            generate: generate,
            consume: { piece in
                spliced.append(contentsOf: piece)
                return true
            }
        )
        return spliced
    }
}
