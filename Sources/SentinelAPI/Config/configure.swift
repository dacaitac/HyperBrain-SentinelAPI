import Vapor

func configure(_ app: Application) throws {
    app.get("health") { _ in ["status": "ok"] }
}
