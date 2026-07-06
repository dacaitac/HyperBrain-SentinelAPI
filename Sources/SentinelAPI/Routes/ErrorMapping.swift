import Vapor

/// Maps EventKit domain errors to Vapor HTTP responses.
extension EventKitService.EventKitError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .notFound, .wrongType: return .notFound
        case .accessDenied: return .forbidden
        case .invalidCalendar, .noDefaultCalendar: return .unprocessableEntity
        }
    }
    var reason: String { description }
}
