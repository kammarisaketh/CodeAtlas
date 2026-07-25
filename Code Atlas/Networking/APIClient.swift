//
//  APIClient.swift
//  Code Atlas
//

import Foundation

enum APIClientError: LocalizedError, Equatable {
    case invalidResponse
    case server(statusCode: Int, message: String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .server(let statusCode, let message):
            "Server error \(statusCode): \(message)"
        case .decodingFailed:
            "The server response could not be decoded."
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let urlSession: URLSession
    var accessTokenProvider: @Sendable () async -> String?

    init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.accessTokenProvider = accessTokenProvider
    }

    func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await perform(path, method: method, body: body)

        do {
            return try JSONDecoder.codeAtlas.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decodingFailed
        }
    }

    func sendWithoutResponse(
        _ path: String,
        method: String,
        body: Encodable? = nil
    ) async throws {
        _ = try await perform(path, method: method, body: body)
    }

    private func perform(_ path: String, method: String, body: Encodable?) async throws -> Data {
        let normalizedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appending(path: "")
        guard let url = URL(string: path, relativeTo: normalizedBaseURL)?.absoluteURL else {
            throw APIClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = await accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder.codeAtlas.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIClientError.server(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

extension JSONDecoder {
    static var codeAtlas: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var codeAtlas: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
