//
//  getGAmes.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-05-03.
//

import Foundation

enum NetworkError: Error {
    case invalidResponse
    case requestFailed
}

class getGames {
    private func performRequest(url: URL, retries: Int = 2) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for _ in 0...retries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidResponse
                }
                return data
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NetworkError.requestFailed
    }

    func getGamesArray(url: URL) async throws -> [Event] {
        let data = try await performRequest(url: url)

        let decoded = try JSONDecoder().decode(
            ScoreboardResponse.self, from: data
        )
        return decoded.events
    }

    func getTennisArray(url: URL) async throws -> [TennisEvent] {
        let data = try await performRequest(url: url)

        let decoded = try JSONDecoder().decode(
            TennisResponse.self, from: data
        )
        return decoded.events
    }
}
