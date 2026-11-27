import Testing
@testable import OwghatCore

@Suite("RefreshCoalescer")
struct RefreshCoalescerTests {
    /// Applies a sequence of steps and returns each step's result.
    /// `.begin(force)` yields `Bool` (run now?); `.finish` yields `Bool?` (follow-up force flag).
    private enum Step {
        case begin(Bool)
        case finish
    }

    private enum Outcome: Equatable {
        case began(Bool)
        case finished(Bool?)
    }

    private func run(_ steps: [Step], on coalescer: inout RefreshCoalescer) -> [Outcome] {
        steps.map { step in
            switch step {
            case .begin(let force): .began(coalescer.begin(force: force))
            case .finish: .finished(coalescer.finish())
            }
        }
    }

    @Test("Idle coalescer runs immediately and goes idle after finish")
    func runsWhenIdle() {
        var coalescer = RefreshCoalescer()
        let outcomes = run([.begin(false), .finish], on: &coalescer)
        #expect(outcomes == [.began(true), .finished(nil)])
        #expect(!coalescer.isRunning)
    }

    @Test("Request during a running refresh is queued, not dropped")
    func queuesDuringRun() {
        var coalescer = RefreshCoalescer()
        let outcomes = run([.begin(true), .begin(true), .finish, .finish], on: &coalescer)
        #expect(outcomes == [.began(true), .began(false), .finished(true), .finished(nil)])
        #expect(!coalescer.isRunning)
    }

    @Test("Several queued requests collapse into one follow-up, forced if any was forced")
    func collapsesQueuedRequests() {
        var coalescer = RefreshCoalescer()
        let outcomes = run(
            [.begin(false), .begin(false), .begin(true), .begin(false), .finish, .finish],
            on: &coalescer
        )
        #expect(outcomes == [
            .began(true), .began(false), .began(false), .began(false),
            .finished(true), .finished(nil),
        ])
    }

    @Test("Unforced queued requests stay unforced")
    func keepsUnforcedFlag() {
        var coalescer = RefreshCoalescer()
        let outcomes = run([.begin(true), .begin(false), .finish, .finish], on: &coalescer)
        #expect(outcomes == [.began(true), .began(false), .finished(false), .finished(nil)])
    }

    @Test("Request queued during the follow-up run triggers another run")
    func queuesDuringFollowUp() {
        var coalescer = RefreshCoalescer()
        let outcomes = run(
            [.begin(false), .begin(true), .finish, .begin(false), .finish, .finish],
            on: &coalescer
        )
        #expect(outcomes == [
            .began(true), .began(false), .finished(true),
            .began(false), .finished(false), .finished(nil),
        ])
        #expect(!coalescer.isRunning)
    }

    @Test("Finish while idle is a no-op")
    func finishWhenIdle() {
        var coalescer = RefreshCoalescer()
        let outcomes = run([.finish, .begin(false)], on: &coalescer)
        #expect(outcomes == [.finished(nil), .began(true)])
    }
}
