import Vapor

@main
struct SentinelAPIApp {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env) { level in
            { label in
                var handler = TimestampLogHandler(label: label)
                handler.logLevel = level
                return handler
            }
        }
        let app = try await Application.make(env)
        do {
            try await configure(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.execute()
        try await app.asyncShutdown()
    }
}
