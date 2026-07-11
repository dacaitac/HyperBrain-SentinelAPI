import Foundation
import Testing
import VaporTesting
@testable import SentinelAPI

/// `POST /commands/replan-agenda` and `POST /commands/sleep-score` (HU-01b slice 2).
/// Uses a recording `UserCommandPublisher` test double — no AWS, no EventKit / TCC needed.
@Suite("User command routes")
struct UserCommandRoutesTests {

    /// Test double for the publisher protocol: records what the routes publish.
    actor RecordingUserCommandPublisher: UserCommandPublisher {
        private(set) var published: [UserCommand] = []

        func publish(_ command: UserCommand) async throws {
            published.append(command)
        }
    }

    private func withCommandsApp(
        _ test: (any TestingApplicationTester, RecordingUserCommandPublisher) async throws -> Void
    ) async throws {
        let recorder = RecordingUserCommandPublisher()
        try await withApp(
            configure: { app in
                ContentConfiguration.global.use(encoder: JSONCoding.makeEncoder(), for: .json)
                ContentConfiguration.global.use(decoder: JSONCoding.makeDecoder(), for: .json)

                let mock = MockEventKitService()
                let loopGuard = LoopGuard()
                let publisher = LoggingEventPublisher(logger: app.logger)
                let snapshotStore = SnapshotStore(
                    fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("sentinel-test-\(UUID().uuidString).json")
                )
                let monitor = ChangeMonitor(
                    eventKit: mock,
                    snapshotStore: snapshotStore,
                    publisher: publisher,
                    loopGuard: loopGuard,
                    logger: app.logger
                )
                let services = SentinelServices(
                    eventKit: mock,
                    snapshotStore: snapshotStore,
                    publisher: publisher,
                    commandPublisher: recorder,
                    consumer: nil,
                    monitor: monitor,
                    loopGuard: loopGuard
                )
                try registerRoutes(app, services)
            },
            { app in
                try await test(try app.testing(), recorder)
            }
        )
    }

    private func decodeAccepted(_ body: ByteBuffer) throws -> CommandAcceptedResponse {
        try JSONCoding.makeDecoder().decode(CommandAcceptedResponse.self, from: Data(buffer: body))
    }

    private func scoreBody(_ json: String) -> ByteBuffer {
        ByteBuffer(string: json)
    }

    private var jsonHeaders: HTTPHeaders {
        ["Content-Type": "application/json"]
    }

    @Test("POST /commands/replan-agenda returns 202 and publishes exactly one REPLAN_AGENDA")
    func replanAgendaPublishes() async throws {
        try await withCommandsApp { tester, recorder in
            try await tester.test(.POST, "commands/replan-agenda") { res async throws in
                #expect(res.status == .accepted)
                let returnedId = try decodeAccepted(res.body).commandId
                let published = await recorder.published
                #expect(published.count == 1)
                #expect(published.first?.commandType == .replanAgenda)
                #expect(published.first?.origin == .user)
                #expect(published.first?.payload == nil)
                #expect(published.first?.commandId == returnedId)
            }
        }
    }

    @Test("POST /commands/sleep-score with a valid score returns 202 and publishes SLEEP_SCORE")
    func sleepScorePublishes() async throws {
        try await withCommandsApp { tester, recorder in
            try await tester.test(
                .POST, "commands/sleep-score",
                headers: jsonHeaders, body: scoreBody(#"{"score":87}"#)
            ) { res async in
                #expect(res.status == .accepted)
            }
            let published = await recorder.published
            #expect(published.count == 1)
            #expect(published.first?.commandType == .sleepScore)
            #expect(published.first?.payload?.score == 87)
            // The date is server-derived: today in the machine's timezone, YYYY-MM-DD.
            #expect(published.first?.payload?.date == UserCommand.localDateString())
        }
    }

    @Test("Boundary scores 0 and 100 are accepted", arguments: [0, 100])
    func boundaryScoresAccepted(score: Int) async throws {
        try await withCommandsApp { tester, recorder in
            try await tester.test(
                .POST, "commands/sleep-score",
                headers: jsonHeaders, body: scoreBody(#"{"score":\#(score)}"#)
            ) { res async in
                #expect(res.status == .accepted)
            }
            let published = await recorder.published
            #expect(published.first?.payload?.score == score)
        }
    }

    @Test("Out-of-range scores are rejected with 400 and nothing is published", arguments: [-1, 101, 1000])
    func outOfRangeScoreRejected(score: Int) async throws {
        try await withCommandsApp { tester, recorder in
            try await tester.test(
                .POST, "commands/sleep-score",
                headers: jsonHeaders, body: scoreBody(#"{"score":\#(score)}"#)
            ) { res async in
                #expect(res.status == .badRequest)
            }
            let published = await recorder.published
            #expect(published.isEmpty)
        }
    }

    @Test("Two POSTs publish two distinct command_ids (fresh UUID per request)")
    func distinctCommandIds() async throws {
        try await withCommandsApp { tester, recorder in
            try await tester.test(.POST, "commands/replan-agenda") { res async in
                #expect(res.status == .accepted)
            }
            try await tester.test(.POST, "commands/replan-agenda") { res async in
                #expect(res.status == .accepted)
            }
            let published = await recorder.published
            #expect(published.count == 2)
            #expect(published[0].commandId != published[1].commandId)
        }
    }
}
