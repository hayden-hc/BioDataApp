//
//  TallyWellAPI.swift
//  BioDataApp
//
//  Calls the local Flask API (Python health_score_model) when running on same network.
//

import Foundation

// MARK: - Request / Response types

struct ScoreRequest {
    let userId: String
    let profile: Profile
    let steps: Double
    let exerciseMinutes: Double
    let sleepHours: Double
    let mood: Double
    let restingHr: Double?
}

struct Profile: Codable {
    var height_cm: Double
    var weight_kg: Double
    var gender: String
    var age: Int
}

struct ScoreResponse: Decodable {
    let score: Double
    let score_raw: Double
    let category_scores: [String: Double]
    let metric_scores: [String: Double]
    let recommendations: [String]
    let baseline_source: String
    let days_of_data: Int
    let weights: WeightsResponse?
}

struct WeightsResponse: Decodable {
    let category_weights: [String: Double]?
    let metric_weights: [String: Double]?
}

struct HistoryDay: Decodable {
    let day: Int
    let score: Double
    let steps: Double
    let exercise_min: Double
    let sleep_hours: Double
    let resting_hr: Double?
    let mood: Double
}

struct HistoryResponse: Decodable {
    let user_id: String?
    let days: [HistoryDay]
}

// MARK: - API errors

enum APIError: Error {
    case invalidURL
    case noData
    case decoding(String)
    case server(String)
    case network(Error)
}

// MARK: - API client

final class TallyWellAPI {

    static let shared = TallyWellAPI()
    private init() {}

    /// Base URL without trailing slash, e.g. "http://192.168.1.42:5001" or "http://localhost:5001"
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "TallyWellAPIBaseURL") ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "TallyWellAPIBaseURL") }
    }

    /// Simulator: localhost. Device: use your Mac's IP (e.g. 192.168.1.42).
    private var defaultBaseURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:5001"
        #else
        return "http://localhost:5001"
        #endif
    }

    /// Default user id for single-user local use.
    var userId: String {
        get {
            if let id = UserDefaults.standard.string(forKey: "TallyWellUserId"), !id.isEmpty {
                return id
            }
            let id = "user-\(UUID().uuidString.prefix(8))"
            UserDefaults.standard.set(id, forKey: "TallyWellUserId")
            return id
        }
        set { UserDefaults.standard.set(newValue, forKey: "TallyWellUserId") }
    }

    // MARK: POST /score

    func postScore(_ req: ScoreRequest) async throws -> ScoreResponse {
        guard let url = URL(string: "\(baseURL)/score") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "user_id": req.userId,
            "profile": [
                "height_cm": req.profile.height_cm,
                "weight_kg": req.profile.weight_kg,
                "gender": req.profile.gender,
                "age": req.profile.age
            ],
            "steps": req.steps,
            "exercise_minutes": req.exerciseMinutes,
            "sleep_hours": req.sleepHours,
            "mood": req.mood
        ]
        if let rhr = req.restingHr, rhr > 0 {
            body["resting_hr"] = rhr
        }

        var data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        if http.statusCode != 200 {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw APIError.server("\(http.statusCode): \(message)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ScoreResponse.self, from: responseData)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: GET /history/<user_id>

    func getHistory(userId: String) async throws -> HistoryResponse {
        let path = "\(baseURL)/history/\(userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId)"
        guard let url = URL(string: path) else { throw APIError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else { throw APIError.noData }
        if http.statusCode != 200 {
            throw APIError.server("\(http.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(HistoryResponse.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: DELETE /reset/<user_id>

    func reset(userId: String) async throws {
        let path = "\(baseURL)/reset/\(userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId)"
        guard let url = URL(string: path) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.noData }
        if http.statusCode != 200 {
            throw APIError.server("\(http.statusCode)")
        }
    }
}
