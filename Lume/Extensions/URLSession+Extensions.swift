import Foundation

final class LumeSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    nonisolated static let shared = LumeSessionDelegate()
    
    private let lock = NSLock()
    private var _ignoreSSLErrors = false
    
    nonisolated var ignoreSSLErrors: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _ignoreSSLErrors
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _ignoreSSLErrors = newValue
        }
    }
    
    override private init() {
        super.init()
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if ignoreSSLErrors,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension URLSession {
    nonisolated static let lume: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: LumeSessionDelegate.shared, delegateQueue: nil)
    }()
}
