import Foundation

/// Supplies a currently-valid bearer credential to `APIClient` — the ONE
/// thing it needs from the identity layer. Kept this narrow (rather than
/// injecting the whole `AuthServiceProtocol`) so `APIClient` depends on the
/// smallest possible abstraction (interface segregation) and so
/// `CoreTests.swift` can mock a token supplier without standing up Firebase.
///
/// `@MainActor` because its only production conformer (`FirebaseAuthService`)
/// is main-actor-confined — the Firebase SDK's `Auth`/`User` types predate
/// Swift 6 auditing, so that class confines every call to one actor. A
/// non-isolated requirement witnessed by a main-actor method is precisely the
/// data race Swift 6 rejects. Isolating the protocol instead of loosening the
/// conformer keeps the confinement honest, and costs callers nothing:
/// `currentIDToken()` is `async`, so the non-isolated `LiveAPIClient` still
/// calls it with a plain `await` across the actor hop.
@MainActor
protocol BearerTokenProviding: Sendable {
    /// Returns a currently-valid Firebase ID token, refreshing it first if
    /// the identity layer considers it stale. Throws if the caller isn't
    /// signed in at all.
    func currentIDToken() async throws -> String
}

/// The full set of Orbit API calls a screen/store ever needs. A protocol
/// (not a concrete type) so `AppStore`/screens depend on an abstraction
/// (`code-standards` facade rule) and `CoreTests.swift`/SwiftUI previews can
/// substitute a mock without a network stack.
protocol APIClientProtocol: Sendable {
    func bootstrapProfile() async throws -> ProfileOut
    func fetchProfile() async throws -> ProfileOut
    func updateProfile(_ update: ProfileUpdate) async throws -> ProfileOut
    func signOut() async throws
    func deleteAccount() async throws

    func fetchQuickFoods() async throws -> [QuickFood]
    func createFoodEntry(_ entry: FoodEntryCreate) async throws -> FoodEntry
    func fetchFuelDay(dayKey: String) async throws -> FuelDay

    func fetchTrainDay(dayKey: String) async throws -> TrainDay
    func markSetDone(_ toggle: SetToggleCreate) async throws -> SetEvent
    func unmarkSet(_ identifier: SetIdentifier) async throws

    func fetchBodyDay(dayKey: String) async throws -> BodyDay

    func logWeight(_ entry: WeightEntryCreate) async throws -> WeightEntry
    func fetchWeightWindow() async throws -> WeightWindow
}

/// `URLSession`-backed live implementation of `APIClientProtocol` — the ONE
/// place the app builds an `URLRequest`/decodes an error envelope
/// (`swift-conventions`: "a typed client facade... views/models depend on
/// the protocol"). All-`let` stored properties, so this is `Sendable` by
/// construction (no locking needed): a fresh `JSONEncoder`/`JSONDecoder` is
/// built per call rather than cached, since Foundation does not document
/// those types as safe to share/mutate concurrently.
final class LiveAPIClient: APIClientProtocol, Sendable {
    private let baseURL: URL
    private let urlSession: URLSession
    private let tokenProvider: BearerTokenProviding

    init(baseURL: URL, urlSession: URLSession = .shared, tokenProvider: BearerTokenProviding) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.tokenProvider = tokenProvider
    }

    // MARK: - Profile

    func bootstrapProfile() async throws -> ProfileOut {
        try await send(.post, path: "/me/bootstrap", body: EmptyRequestBody())
    }

    func fetchProfile() async throws -> ProfileOut {
        try await send(.get, path: "/profile")
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> ProfileOut {
        try await send(.patch, path: "/profile", body: update)
    }

    func signOut() async throws {
        try await sendNoContent(.post, path: "/me/signout", body: EmptyRequestBody())
    }

    func deleteAccount() async throws {
        try await sendNoContent(.delete, path: "/me", body: EmptyRequestBody())
    }

    // MARK: - Fuel

    func fetchQuickFoods() async throws -> [QuickFood] {
        try await send(.get, path: "/catalog/quick-foods")
    }

    func createFoodEntry(_ entry: FoodEntryCreate) async throws -> FoodEntry {
        try await send(.post, path: "/fuel/entries", body: entry)
    }

    func fetchFuelDay(dayKey: String) async throws -> FuelDay {
        try await send(.get, path: "/fuel", query: [URLQueryItem(name: "day_key", value: dayKey)])
    }

    // MARK: - Train

    func fetchTrainDay(dayKey: String) async throws -> TrainDay {
        try await send(.get, path: "/train", query: [URLQueryItem(name: "day_key", value: dayKey)])
    }

    func markSetDone(_ toggle: SetToggleCreate) async throws -> SetEvent {
        try await send(.post, path: "/train/sets", body: toggle)
    }

    func unmarkSet(_ identifier: SetIdentifier) async throws {
        try await sendNoContent(.delete, path: "/train/sets", body: identifier)
    }

    // MARK: - Body

    func fetchBodyDay(dayKey: String) async throws -> BodyDay {
        try await send(.get, path: "/body", query: [URLQueryItem(name: "day_key", value: dayKey)])
    }

    // MARK: - Weight

    func logWeight(_ entry: WeightEntryCreate) async throws -> WeightEntry {
        try await send(.post, path: "/weight", body: entry)
    }

    func fetchWeightWindow() async throws -> WeightWindow {
        try await send(.get, path: "/weight")
    }

    // MARK: - Request plumbing (private — every public method above funnels through this)

    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// A no-fields request body for the NO-BODY endpoints (`schemas.common.
    /// EmptyBody`'s client-side counterpart) — encodes to `{}`, matching
    /// what `extra="forbid"` on an empty model accepts.
    private struct EmptyRequestBody: Encodable {}

    /// GET-shaped call: no request body, decodes a `Response`.
    private func send<Response: Decodable>(
        _ method: HTTPMethod, path: String, query: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try await buildRequest(method, path: path, query: query, bodyData: nil)
        return try await execute(request, decoding: Response.self)
    }

    /// Write-shaped call with a JSON-encoded body, decodes a `Response`.
    private func send<Body: Encodable, Response: Decodable>(
        _ method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: Body
    ) async throws -> Response {
        let bodyData = try Self.makeEncoder().encode(body)
        let request = try await buildRequest(method, path: path, query: query, bodyData: bodyData)
        return try await execute(request, decoding: Response.self)
    }

    /// Write-shaped call whose success response has no body (204).
    private func sendNoContent<Body: Encodable>(
        _ method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: Body
    ) async throws {
        let bodyData = try Self.makeEncoder().encode(body)
        let request = try await buildRequest(method, path: path, query: query, bodyData: bodyData)
        _ = try await executeExpectingNoContent(request)
    }

    private func buildRequest(
        _ method: HTTPMethod, path: String, query: [URLQueryItem], bodyData: Data?
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw AppError.network(message: "Could not construct request URL for \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw AppError.network(message: "Could not construct request URL for \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = bodyData

        // Every Orbit route requires auth except `/health` (never called from
        // this client) — fetch the token fresh per request rather than
        // caching it here, so a mid-session refresh is always honored.
        let token = try await tokenProvider.currentIDToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return request
    }

    private func execute<Response: Decodable>(_ request: URLRequest, decoding: Response.Type) async throws -> Response {
        let data = try await executeExpectingNoContent(request)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw AppError.decodingFailed(message: "\(Response.self): \(error.localizedDescription)")
        }
    }

    /// Runs the request and returns the raw success-response body (empty for
    /// a 204) — the one place that inspects the HTTP status and translates a
    /// non-2xx response to a typed `AppError` via the error-envelope facade.
    @discardableResult
    private func executeExpectingNoContent(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AppError.network(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(message: "Response was not an HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw try mapErrorResponse(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
        }
        return data
    }

    private func mapErrorResponse(statusCode: Int, data: Data, response: HTTPURLResponse) throws -> AppError {
        let retryAfterSeconds = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init)
        guard let envelope = try? Self.makeDecoder().decode(ErrorEnvelopeResponse.self, from: data) else {
            // The server's own error-envelope facade (`edge/errors.py`) is
            // the only thing that ever produces a non-2xx response in this
            // API, so an undecodable body here means something OUTSIDE the
            // app (a proxy, a captive portal) intercepted the request —
            // surface it as a server error with the raw status, not silently.
            return .server(statusCode: statusCode, message: "Unrecognized error response (status \(statusCode))")
        }
        return AppErrorMapping.map(statusCode: statusCode, envelope: envelope, retryAfterSeconds: retryAfterSeconds)
    }

    /// ISO-8601, no fractional seconds — matches Pydantic's `AwareDatetime`
    /// serialization verified against real captured responses this session
    /// (e.g. `"logged_at": "2026-07-25T01:54:17Z"`).
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
