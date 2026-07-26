import Foundation

/// The app-facing error type every layer above `APIClient` sees — mirrors the
/// backend's error-envelope facade (`src/orbit/edge/errors.py`:
/// `{"error": {"code","message","requestId"}}`) so a screen never has to
/// pattern-match on raw `URLError`/HTTP status codes (`swift-conventions`:
/// "Map lower-layer errors to a small app-facing set at the service facade —
/// views don't see `URLError` directly").
enum AppError: Error, Equatable, Sendable {
    /// 401 — the bearer token is missing, malformed, expired, or revoked.
    case unauthorized(message: String)
    /// 403 — authenticated, but not permitted (declared for completeness; no
    /// route in this app currently returns it — there are no roles to deny).
    case forbidden(message: String)
    /// 404 — the resource doesn't exist, or (per this API's own convention)
    /// the caller hasn't called `POST /me/bootstrap` yet.
    case notFound(message: String)
    /// 409 — a uniqueness/state conflict (e.g. a DB unique-constraint hit).
    case conflict(message: String)
    /// 422 — request validation failed (schema violation, XOR-contract
    /// violation, out-of-bounds value, mass-assignment rejection, etc.).
    case validationFailed(message: String)
    /// 429 — rate-limited; `retryAfterSeconds` echoes the `Retry-After`
    /// header when the server sent one (`edge/ratelimit.py` always does).
    case rateLimited(message: String, retryAfterSeconds: Int?)
    /// Any other 4xx/5xx the server's error envelope reports (including the
    /// generic `500 internal` and the account-deletion `502` post-commit
    /// Firebase-failure case) — collapsed to one case with the real status
    /// code preserved, rather than a dedicated case per status this app has
    /// no distinct behavior for (YAGNI).
    case server(statusCode: Int, message: String)
    /// The request never got a server response at all (no connectivity, DNS
    /// failure, timeout, TLS failure) — wraps `URLError.localizedDescription`
    /// rather than the raw `URLError` (views never see `URLError` directly).
    case network(message: String)
    /// The server responded with a 2xx status but the body didn't match the
    /// `Codable` model this endpoint expects — a contract mismatch worth
    /// surfacing distinctly (it means the client and server schemas have
    /// drifted), not the same as "the network failed."
    case decodingFailed(message: String)

    /// A short, user-presentable string for an `.alert`/toast — never the
    /// server's raw internal detail for a `.server` case beyond what the
    /// error envelope already redacts server-side.
    var userFacingMessage: String {
        switch self {
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .forbidden(let message), .notFound(let message), .conflict(let message), .validationFailed(let message):
            return message
        case .rateLimited: return "Too many requests — please try again in a moment."
        case .server: return "Something went wrong on our end. Please try again."
        case .network: return "Couldn't reach Orbit — check your connection and try again."
        case .decodingFailed: return "Orbit received an unexpected response. Please try again."
        }
    }

    /// Whether retrying the exact same request without user action (a
    /// silent auto-retry, not a manual "Retry" tap) is ever reasonable —
    /// used to decide whether a screen's error state offers a retry
    /// affordance at all (plan §Frontend: "error = clear state + manual
    /// retry, no offline queue").
    var isRetryable: Bool {
        switch self {
        case .network, .server, .rateLimited: return true
        case .unauthorized, .forbidden, .notFound, .conflict, .validationFailed, .decodingFailed: return false
        }
    }
}

/// The wire shape of every error response `edge/errors.py::build_error_response`
/// produces — decoded once, in `APIClient`, then translated to `AppError`.
struct ErrorEnvelopeResponse: Decodable, Equatable, Sendable {
    struct ErrorDetail: Decodable, Equatable, Sendable {
        let code: String
        let message: String
        let requestId: String?
    }

    let error: ErrorDetail
}

/// Central facade mapping a decoded error envelope + HTTP status to an
/// `AppError` — the ONE place that knows the backend's error `code` strings
/// (`unauthorized`/`forbidden`/`not_found`/`conflict`/`validation_failed`/
/// `rate_limited`), so a new call site never re-implements this switch.
enum AppErrorMapping {
    static func map(statusCode: Int, envelope: ErrorEnvelopeResponse, retryAfterSeconds: Int?) -> AppError {
        let message = envelope.error.message
        switch envelope.error.code {
        case "unauthorized": return .unauthorized(message: message)
        case "forbidden": return .forbidden(message: message)
        case "not_found": return .notFound(message: message)
        case "conflict": return .conflict(message: message)
        case "validation_failed": return .validationFailed(message: message)
        case "rate_limited": return .rateLimited(message: message, retryAfterSeconds: retryAfterSeconds)
        default:
            // Covers `"internal"` (the generic 500) and `"error"` (any 4xx/5xx
            // status the backend's `_CODE_BY_STATUS` map doesn't name, e.g.
            // the account-deletion 502) — both real, verified-in-repo shapes
            // from `src/orbit/edge/errors.py`, not a guess.
            return .server(statusCode: statusCode, message: message)
        }
    }
}
