import Vapor

@main
struct SentinelAPIApp {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        defer { app.shutdown() }
        try configure(app)
        try await app.execute()
    }
}
