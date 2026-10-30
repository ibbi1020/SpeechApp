import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Opens Google in the system browser and returns the account id (`sub`).
/// The identity token and the refresh token are not stored.
@MainActor
final class GoogleSignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn(clientID: String) async throws -> String {
        let scheme = Self.reversedScheme(from: clientID)
        let verifier = Self.randomToken()
        let state = Self.randomToken()
        let redirect = "\(scheme):/oauth2callback"
        guard let url = Self.authorizationURL(
            clientID: clientID,
            redirect: redirect,
            verifier: verifier,
            state: state
        ) else {
            throw GoogleSignInFailure.failed
        }

        let callback = try await start(url: url, scheme: scheme)
        let fields = Self.fields(in: callback)
        if fields["error"] == "access_denied" {
            throw GoogleSignInFailure.canceled
        }
        guard fields["state"] == state, let code = fields["code"], code.isEmpty == false else {
            throw GoogleSignInFailure.failed
        }
        let idToken = try await Self.exchange(
            code: code,
            clientID: clientID,
            redirect: redirect,
            verifier: verifier
        )
        guard let subject = Self.subject(in: idToken) else {
            throw GoogleSignInFailure.failed
        }
        return subject
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func start(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInFailure.canceled)
                    return
                }
                if error != nil {
                    continuation.resume(throwing: GoogleSignInFailure.failed)
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: GoogleSignInFailure.failed)
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if session.start() == false {
                continuation.resume(throwing: GoogleSignInFailure.failed)
            }
        }
    }

    private static func authorizationURL(
        clientID: String,
        redirect: String,
        verifier: String,
        state: String
    ) -> URL? {
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        parts?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return parts?.url
    }

    /// Public iOS clients use PKCE. No client secret is sent.
    private static func exchange(
        code: String,
        clientID: String,
        redirect: String,
        verifier: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleSignInFailure.failed
        }
        return idToken
    }

    private static func subject(in idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              subject.isEmpty == false else {
            return nil
        }
        return subject
    }

    private static func reversedScheme(from clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fields(in url: URL) -> [String: String] {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            if let value = item.value { fields[item.name] = value }
        }
        if let fragment = parts.fragment,
           let fragmentParts = URLComponents(string: "https://orator.local?\(fragment)") {
            for item in fragmentParts.queryItems ?? [] {
                if let value = item.value { fields[item.name] = value }
            }
        }
        return fields
    }
}

enum GoogleSignInFailure: Error, Sendable {
    case canceled
    case failed
}
