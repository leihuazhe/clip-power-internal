import Foundation
import LocalAuthentication

enum BiometricGateError: Error {
    case authenticationFailed(String)
}

/// Touch ID / 系统密码鉴权网关。
/// 短时宽限期内复用同一个已通过验证的 LAContext，避免连续操作反复弹窗
/// （Keychain 在 LAContext 近期验证成功后可直接放行，不会二次弹窗）。
actor BiometricGate {
    static let shared = BiometricGate()

    private var cachedContext: LAContext?
    private var lastSuccessAt: Date?
    private let gracePeriod: TimeInterval

    init(gracePeriod: TimeInterval = 15) {
        self.gracePeriod = gracePeriod
    }

    /// 鉴权成功后，在 actor 内部同步执行 `operation`（LAContext 本身不 Sendable，
    /// 因此不会跨隔离域传出；只有 `operation` 的 Sendable 结果会跨界返回）。
    func authenticate<T: Sendable>(
        reason: String,
        operation: @Sendable (LAContext) throws -> T
    ) async throws -> T {
        let context = try await resolveAuthenticatedContext(reason: reason)
        return try operation(context)
    }

    private func resolveAuthenticatedContext(reason: String) async throws -> LAContext {
        if let cachedContext, let lastSuccessAt, Date().timeIntervalSince(lastSuccessAt) < gracePeriod {
            return cachedContext
        }

        let context = LAContext()
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            throw BiometricGateError.authenticationFailed(evalError?.localizedDescription ?? String(localized: "此设备不支持身份验证"))
        }

        try await evaluate(context: context, reason: reason)
        cachedContext = context
        lastSuccessAt = Date()
        return context
    }

    func invalidateGracePeriod() {
        cachedContext = nil
        lastSuccessAt = nil
    }

    private func evaluate(context: LAContext, reason: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BiometricGateError.authenticationFailed(error?.localizedDescription ?? String(localized: "验证未通过")))
                }
            }
        }
    }
}
