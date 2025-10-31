//
//  RedditAPI.swift
//  winston
//
//  Created by Igor Marcossi on 24/06/23.
//

import Foundation
import KeychainAccess
import Alamofire
import SwiftUI
import Defaults
import Combine
import SwiftData

@Observable
class RedditAPI {
    static let shared = RedditAPI()
    static let winstonAPIBase = "https://winston.lo.cafe/api"
    static let redditApiURLBase = "https://oauth.reddit.com"
    static let redditWWWApiURLBase = "https://www.reddit.com"
    static let appRedirectURI: String = "https://app.winston.cafe/auth-success"
    
    var lastAuthState: String?
    var me: User?
    
    // Optional SwiftData ModelContext for logging
    var modelContext: ModelContext?
    func setModelContext(_ context: ModelContext) { self.modelContext = context }
    
    // This is a replacement for getRequestHeader. We need to replace every instance of the former by this one
    func fetchRequestHeaders(
        force: Bool = false,
        includeAuth: Bool = true,
        altCredential: RedditCredential? = nil,
        saveToken: Bool = true
    ) async -> HTTPHeaders? {
        var headers: HTTPHeaders = [
            "User-Agent": RedditCredential.defaultUserAgent()
        ]
        if includeAuth {
            if
                let selectedCredential = altCredential ?? RedditCredentialsManager.shared.selectedCredential,
                let accessToken = await selectedCredential.getUpToDateToken(forceRenew: force, saveToken: saveToken)
            {
                headers["Authorization"] = "Bearer \(accessToken.token)"
                headers["User-Agent"] = selectedCredential.userAgent
            } else {
                return nil
            }
        }
        
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
        
        return headers
    }
    
    private let reqAttempts = 2
    
    private let reqModifier: Session.RequestModifier = { urlReq in
        urlReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    }

    // Normalize endpoint labels to group by route rather than specific IDs
    private func normalizedEndpointLabel(from url: String, method: HTTPMethod) -> String {
        // Strip query string
        let base = url.components(separatedBy: "?").first ?? url
        // Attempt to map known Reddit routes to templates
        // Examples:
        // - https://oauth.reddit.com/r/{sub}/comments/{postId}/... -> /r/:sub/comments/:post
        // - https://oauth.reddit.com/r/{sub}/{sort} -> /r/:sub/:sort
        // - https://oauth.reddit.com/api/info -> /api/info
        // - https://oauth.reddit.com/api/vote -> /api/vote
        // - https://oauth.reddit.com/user/{name}/about -> /user/:name/about
        // - https://oauth.reddit.com/api/search_reddit_names -> /api/search_reddit_names
        // - https://oauth.reddit.com/_ -> /subreddits/mine

        func path(from full: String) -> String {
            if let u = URL(string: full), let host = u.host {
                var path = u.path
                // Normalize double slashes
                while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
                // If host is oauth.reddit.com or www.reddit.com, keep path; otherwise include host to avoid collisions
                if host.contains("reddit.com") { return path }
                return "//" + host + path
            }
            return full
        }

        var p = path(from: base)

        // Replace UUID-like or base36 id segments with placeholders
        // Reddit IDs are often base36; we approximate by replacing long alnum segments
        let components = p.split(separator: "/").map(String.init)
        var normalized: [String] = []
        var i = 0
        while i < components.count {
            let seg = components[i]
            switch seg.lowercased() {
            case "r":
                normalized.append("r"); i += 1
                if i < components.count { normalized.append(":sub"); i += 1 }
            case "comments":
                normalized.append("comments"); i += 1
                if i < components.count { normalized.append(":post"); i += 1 }
            case "user":
                normalized.append("user"); i += 1
                if i < components.count { normalized.append(":user"); i += 1 }
            default:
                // Known API endpoints
                if seg == "api" || seg == "message" || seg == "subreddits" || seg == "by_id" {
                    normalized.append(seg); i += 1
                } else if seg.count >= 6 && seg.range(of: "^[A-Za-z0-9_\\-]+$", options: .regularExpression) != nil {
                    // Likely identifier or sort; map common sorts, else placeholder
                    let commonSorts = ["hot","new","top","best","rising","controversial"]
                    if commonSorts.contains(seg) {
                        normalized.append(":sort")
                    } else {
                        normalized.append(":id")
                    }
                    i += 1
                } else {
                    normalized.append(seg); i += 1
                }
            }
        }

        // Join back into a path and prefix method for clarity
        var label = "/" + normalized.joined(separator: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if label.hasSuffix("/") { label.removeLast() }
        return label
    }
    
    func doRequest<D: Decodable, P: Encodable>(
        _ url: String,
        authenticated: Bool = true,
        method: HTTPMethod,
        params: P? = nil,
        paramsLocation: URLEncodedFormParameterEncoder.Destination = .httpBody,
        decodable: D.Type,
        altCredential: RedditCredential? = nil,
        attempt: Int = 0,
        saveToken: Bool = true
    ) async -> Result<D, AFError> {
        let startedAt = Date()
        let endpointLabel = normalizedEndpointLabel(from: url, method: method)
        let methodLabel = method.rawValue

        let result = await self._doRequest(authenticated: authenticated, altCredential: altCredential, saveToken: saveToken) { headers in
            let req = AF.request(url, method: method, parameters: params, encoder: URLEncodedFormParameterEncoder(destination: paramsLocation), headers: headers, requestModifier: reqModifier).validate()
            return await req.serializingDecodable(decodable).response.result
        }
        switch result {
        case .success(_):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .success, code: nil, errorDescription: nil, context: modelContext)
        case .failure(let err):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .failure, code: err.responseCode, errorDescription: err.errorDescription, context: modelContext)
        }
        return result
    }
    
    func doRequest<D: Decodable>(
        _ url: String,
        authenticated: Bool = true,
        method: HTTPMethod,
        decodable: D.Type,
        altCredential: RedditCredential? = nil,
        attempt: Int = 0,
        saveToken: Bool = true
    ) async -> Result<D, AFError> {
        let startedAt = Date()
        let endpointLabel = normalizedEndpointLabel(from: url, method: method)
        let methodLabel = method.rawValue

        let result = await self._doRequest(authenticated: authenticated, altCredential: altCredential, saveToken: saveToken) { headers in
            let req = AF.request(url, method: method, parameters: ["raw_json": 1], headers: headers, requestModifier: reqModifier).validate()
            return await req.serializingDecodable(decodable).response.result
        }
        switch result {
        case .success(_):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .success, code: nil, errorDescription: nil, context: modelContext)
        case .failure(let err):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .failure, code: err.responseCode, errorDescription: err.errorDescription, context: modelContext)
        }
        return result
    }
    
    func doRequest<P: Encodable>(
        _ url: String,
        authenticated: Bool = true,
        method: HTTPMethod,
        params: P,
        paramsLocation: URLEncodedFormParameterEncoder.Destination = .httpBody,
        altCredential: RedditCredential? = nil,
        attempt: Int = 0,
        saveToken: Bool = true
    ) async -> Result<String, AFError> {
        let startedAt = Date()
        let endpointLabel = normalizedEndpointLabel(from: url, method: method)
        let methodLabel = method.rawValue

        let result = await self._doRequest(authenticated: authenticated, altCredential: altCredential, saveToken: saveToken) { headers in
            let req = AF.request(url, method: method, parameters: params, encoder: URLEncodedFormParameterEncoder(destination: paramsLocation), headers: headers, requestModifier: reqModifier).validate()
            return await req.serializingString().result
        }
        switch result {
        case .success(_):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .success, code: nil, errorDescription: nil, context: modelContext)
        case .failure(let err):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .failure, code: err.responseCode, errorDescription: err.errorDescription, context: modelContext)
        }
        return result
    }
    
    func doRequest(
        _ url: String,
        authenticated: Bool = true,
        method: HTTPMethod,
        paramsLocation: URLEncodedFormParameterEncoder.Destination = .httpBody,
        altCredential: RedditCredential? = nil,
        attempt: Int = 0,
        saveToken: Bool = true
    ) async -> Result<String, AFError> {
        let startedAt = Date()
        let endpointLabel = normalizedEndpointLabel(from: url, method: method)
        let methodLabel = method.rawValue

        let result = await self._doRequest(authenticated: authenticated, altCredential: altCredential, saveToken: saveToken) { headers in
            let req = AF.request(url, method: method, parameters: ["raw_json": 1], headers: headers).validate()
            return await req.serializingString().result
        }
        switch result {
        case .success(_):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .success, code: nil, errorDescription: nil, context: modelContext)
        case .failure(let err):
            APIRequestLogger.shared.log(endpoint: endpointLabel, fullEndpoint: url.replacingOccurrences(of: RedditAPI.redditApiURLBase, with: ""), method: methodLabel, startedAt: startedAt, endedAt: Date(), status: .failure, code: err.responseCode, errorDescription: err.errorDescription, context: modelContext)
        }
        return result
    }
    
    func _doRequest<D: Decodable>(
        attempt: Int = 0,
        forceAuth: Bool = false,
        authenticated: Bool = true,
        altCredential: RedditCredential? = nil,
        saveToken: Bool = true,
        req: (HTTPHeaders) async -> Result<D, AFError>
    ) async -> Result<D, AFError> {
        guard let headers = await fetchRequestHeaders(force: forceAuth, includeAuth: authenticated, altCredential: altCredential, saveToken: saveToken) else { return .failure(.serverTrustEvaluationFailed(reason: .noPublicKeysFound)) }
        
        let result = await req(headers)
        if case .failure(let error) = result {
            print(error)
            if attempt < (authenticated ? 3 : 2) {
                return await self._doRequest(attempt: attempt + 1, forceAuth: authenticated && attempt == 1, authenticated: authenticated, altCredential: altCredential, saveToken: saveToken, req: req)
            }
            switch error.responseCode {
            case 401:
                break
            default:
                break
            }
        }
        return result
    }
    
    func injectFirstAccessTokenInto(_ credential: inout RedditCredential, authCode: String) async -> Bool {
        if !credential.apiAppID.isEmpty && !credential.apiAppSecret.isEmpty {
            let headers = await fetchRequestHeaders(includeAuth: false)
            var code = authCode
            if code.hasSuffix("#_") {
                code = "\(code.dropLast(2))"
            }
            let payload = GetAccessTokenPayload(code: authCode)
            let response = await AF.request(
                "\(RedditAPI.redditWWWApiURLBase)/api/v1/access_token",
                method: .post,
                parameters: payload,
                encoder: URLEncodedFormParameterEncoder(destination: .httpBody),
                headers: headers
            )
                .authenticate(username: credential.apiAppID, password: credential.apiAppSecret, persistence: .none)
                .serializingDecodable(GetAccessTokenResponse.self).response
            switch response.result {
            case .success(let data):
                let newAcessToken = RedditCredential.AccessToken(token: data.access_token, expiration: data.expires_in, lastRefresh: Date())
                credential.refreshToken = data.refresh_token
                credential.accessToken = newAcessToken
                if let meData = await self.fetchMe(force: true, altCredential: credential, saveToken: false) {
                    credential.userName = meData.name
                    if let avatar = (meData.subreddit?.icon_img ?? meData.icon_img ?? meData.snoovatar_img), let rootAvatar = rootURL(avatar)?.absoluteString {
                        credential.profilePicture = rootAvatar
                    }
                    return true
                }
                return true
            case .failure(let error):
                print(error)
                return false
            }
        }
        return false
    }
    
    func getAuthCodeFromURL(_ rawUrl: URL) -> String? {
        if let url = URL(string: rawUrl.absoluteString.replacingOccurrences(of: "winstonapp://", with: "https://app.winston.cafe/")), url.lastPathComponent == "auth-success", let query = URLComponents(url: url, resolvingAgainstBaseURL: false), let state = query.queryItems?.first(where: { $0.name == "state" })?.value, let code = query.queryItems?.first(where: { $0.name == "code" })?.value, state == lastAuthState {
            //      let res = await injectFirstAccessTokenInto(&credential, authCode: code)
            //      lastAuthState = nil
            //      return res
            return code
        } else {
            return nil
        }
    }
    
    func  getAuthorizationCodeURL(_ appID: String) -> URL {
        let response_type: String = "code"
        let state: String = UUID().uuidString
        let redirect_uri: String = RedditAPI.appRedirectURI
        let duration: String = "permanent"
        let scope: String = "identity,edit,flair,history,modconfig,modflair,modlog,modposts,modwiki,mysubreddits,privatemessages,read,report,save,submit,subscribe,vote,wikiedit,wikiread"
        
        lastAuthState = state
        
        return URL(string: "https://www.reddit.com/api/v1/authorize.compact?client_id=\(appID.trimmingCharacters(in: .whitespaces))&response_type=\(response_type)&state=\(state)&redirect_uri=\(redirect_uri)&duration=\(duration)&scope=\(scope)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
    }
    
    struct RefreshAccessTokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Int
        let scope: String
    }
    
    struct GetAccessTokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let refresh_token: String
        let scope: String
        let expires_in: Int
    }
    
    struct RefreshAccessTokenPayload: Encodable {
        let grant_type = "refresh_token"
        let refresh_token: String
    }
    
    struct GetAccessTokenPayload: Encodable {
        let grant_type = "authorization_code"
        let code: String
        let redirect_uri = RedditAPI.appRedirectURI
    }
}

struct ListingChild<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
    let kind: String?
    var data: T?
}

struct Listing<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
    let kind: String?
    var data: ListingData<T>?
}

struct ListingData<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
    let after: String?
    let dist: Int?
    let modhash: String?
    let geo_filter: String?
    var children: [ListingChild<T>]?
}

enum Either<A: Codable & Hashable, B: Codable & Hashable>: Codable, Hashable {
    case first(A)
    case second(B)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        do {
            let firstType = try container.decode(A.self)
            self = .first(firstType)
        } catch let firstError {
            do {
                let secondType = try container.decode(B.self)
                self = .second(secondType)
            } catch let secondError {
                let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Type mismatch for both types.", underlyingError: Swift.DecodingError.typeMismatch(Any.self, DecodingError.Context.init(codingPath: decoder.codingPath, debugDescription: "First type error: \(firstError). Second type error: \(secondError)")))
                throw DecodingError.dataCorrupted(context)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .first(let value):
            try container.encode(value)
        case .second(let value):
            try container.encode(value)
        }
    }
    
    func isFirst() -> Bool {
        switch self {
        case .first(let _):
            return true
        case .second(let _):
            return false
        }
    }
    
    func isSecond() -> Bool {
        return !isFirst()
    }
}

