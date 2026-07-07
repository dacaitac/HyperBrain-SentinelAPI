import Foundation
import Vapor

/// Boots SentinelAPI: registers the wire coders, loads config + credentials, builds the
/// EventKit/SQS actors and starts the change monitor and command consumer.
func configure(_ app: Application) async throws {
    // RNF-09: the REST API must only be reachable over the tailnet — never bind 0.0.0.0.
    // At login the LaunchAgent can start before tailscaled brings the interface up, so retry
    // briefly before degrading to loopback (SQS keeps working either way).
    var bind = BindAddress.resolve()
    for _ in 0..<5 where bind.isFallback && !AppConfiguration.isLocalTest() {
        try await Task.sleep(for: .seconds(2))
        bind = BindAddress.resolve()
    }
    app.http.server.configuration.hostname = bind.hostname
    if bind.isFallback && !AppConfiguration.isLocalTest() {
        app.logger.warning("Tailscale interface not found — REST API bound to loopback only (set SENTINEL_HOSTNAME to override)")
    } else {
        app.logger.info("REST API binding to \(bind.hostname)")
    }

    // REST bodies use the same snake_case + ISO-8601 contract as the SQS messages.
    ContentConfiguration.global.use(encoder: JSONCoding.makeEncoder(), for: .json)
    ContentConfiguration.global.use(decoder: JSONCoding.makeDecoder(), for: .json)

    let eventKit = EventKitService()
    let snapshotStore = SnapshotStore(fileURL: try snapshotURL())
    let loopGuard = LoopGuard()

    let publisher: any EventPublisher
    let consumer: SQSConsumer?

    if AppConfiguration.isLocalTest() {
        // Dev machine: log detected changes instead of publishing; no AWS, no command consumer.
        app.logger.warning("SENTINEL_LOCAL_TEST=true — logging changes instead of publishing to SQS")
        publisher = LoggingEventPublisher(logger: app.logger)
        consumer = nil
    } else {
        let config = try AppConfiguration.load()
        // Feed the AWS default credential chain from the keychain-sourced config (never on disk).
        setenv("AWS_ACCESS_KEY_ID", config.credentials.accessKeyID, 1)
        setenv("AWS_SECRET_ACCESS_KEY", config.credentials.secretAccessKey, 1)
        setenv("AWS_REGION", config.awsRegion, 1)

        publisher = try await SQSPublisher(region: config.awsRegion, queueURL: config.syncEventsQueueURL)
        if AppConfiguration.isConsumerEnabled() {
            consumer = try await SQSConsumer(
                region: config.awsRegion,
                queueURL: config.appleCommandsQueueURL,
                resultsQueueURL: config.appleCommandsResultsQueueURL,
                eventKit: eventKit,
                loopGuard: loopGuard,
                logger: app.logger
            )
        } else {
            app.logger.warning("SENTINEL_CONSUMER_ENABLED=false — publishing only, apple-commands.fifo consumer disabled")
            consumer = nil
        }
    }

    let monitor = ChangeMonitor(
        eventKit: eventKit,
        snapshotStore: snapshotStore,
        publisher: publisher,
        loopGuard: loopGuard,
        logger: app.logger
    )

    let services = SentinelServices(
        eventKit: eventKit,
        snapshotStore: snapshotStore,
        publisher: publisher,
        consumer: consumer,
        monitor: monitor,
        loopGuard: loopGuard
    )
    app.sentinel = services

    try registerRoutes(app, services)
    app.lifecycle.use(SentinelLifecycle(services: services))
}

/// Starts the background actors once EventKit access is granted; stops them on shutdown.
private struct SentinelLifecycle: LifecycleHandler {
    let services: SentinelServices

    func didBootAsync(_ application: Application) async throws {
        try await services.eventKit.requestAccess()
        await services.consumer?.start()
        await services.monitor.start()
        if AppConfiguration.isLocalTest() {
            application.logger.info("SentinelAPI started (local test): monitoring EventKit, logging changes")
        } else if services.consumer == nil {
            application.logger.info("SentinelAPI started: monitoring EventKit, publishing to SQS (apple-commands consumer disabled)")
        } else {
            application.logger.info("SentinelAPI started: monitoring EventKit, publishing to SQS and consuming apple-commands.fifo")
        }
    }

    func shutdownAsync(_ application: Application) async {
        await services.monitor.stop()
        await services.consumer?.stop()
    }
}

private func snapshotURL() throws -> URL {
    let base = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("SentinelAPI", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("snapshot.json")
}
