import Foundation
import FoundationModels

/// An optional on-device model can arrange verified explanation sentences.
/// It never generates network conclusions, advice, commands, or configuration.
public struct DiagnosticExplanationService: Sendable {
    public typealias AvailabilityProvider = @Sendable () -> DiagnosticModelAvailability
    public typealias SummaryOrderGenerator = @Sendable (String) async throws -> [Int]

    private let availabilityProvider: AvailabilityProvider
    private let generate: SummaryOrderGenerator
    private let maximumGenerationDuration: Duration

    public init() {
        self.init(availability: Self.systemAvailability, generate: Self.generateSummaryOrder)
    }

    /// Dependency injection also lets tests cover unavailable assets, timeouts,
    /// refusal, and cancellation without invoking a real model.
    public init(
        availability: @escaping AvailabilityProvider,
        generate: @escaping SummaryOrderGenerator,
        maximumGenerationDuration: Duration = .seconds(20)
    ) {
        availabilityProvider = availability
        self.generate = generate
        self.maximumGenerationDuration = maximumGenerationDuration
    }

    public func availability() -> DiagnosticModelAvailability {
        availabilityProvider()
    }

    public func ruleExplanation(
        context: DiagnosticExplanationContext,
        language: AppLanguage
    ) -> DiagnosticExplanation {
        let chinese = Self.usesChinese(language)
        func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        var observations: [String] = []
        var nextSteps: [String] = []

        if context.hasSystemProxyError {
            observations.append(text(
                "系统代理操作报告了错误，部分代理设置可能仍未恢复。",
                "A system proxy operation reported an error; some proxy settings may still need restoration."
            ))
            nextSteps.append(text(
                "先在 Nexora 中重试恢复系统代理，并检查错误是否消失。",
                "Retry restoring the system proxy in Nexora and check whether the error clears."
            ))
        }

        if context.expectsCoreListeners, context.missingListenerCount > 0 {
            observations.append(text(
                "核心应当运行，但有 \(context.missingListenerCount) 个预期端口没有监听器。",
                "The core is expected to be running, but \(context.missingListenerCount) expected listeners are missing."
            ))
            nextSteps.append(text(
                "查看端口雷达和核心状态；可尝试重启核心，再重新诊断。",
                "Inspect Port Radar and the core status; try restarting the core, then run the diagnosis again."
            ))
        }
        if context.foreignListenerCount > 0 {
            observations.append(text(
                "有 \(context.foreignListenerCount) 个监听器的进程编号与当前核心不一致。",
                "\(context.foreignListenerCount) listeners have a process ID that differs from the current core."
            ))
            nextSteps.append(text(
                "在端口雷达核对占用进程，再决定是否释放或更换端口。",
                "Check the owning process in Port Radar before deciding whether to release or change a port."
            ))
        }
        if context.unknownListenerOwnerCount > 0 {
            observations.append(text(
                "有 \(context.unknownListenerOwnerCount) 个端口已在监听，但现有进程信息不足以确认归属；这本身不证明端口冲突。",
                "\(context.unknownListenerOwnerCount) ports are listening, but process ownership is unknown; that alone does not establish a port conflict."
            ))
        }

        if context.rateLimitedEndpointCount > 0 {
            observations.append(text(
                "有 \(context.rateLimitedEndpointCount) 个探测收到 HTTP 429，表示请求被限流；这不能单独证明整个网络断开。",
                "\(context.rateLimitedEndpointCount) probes received HTTP 429, which indicates rate limiting; this alone does not prove the whole network is offline."
            ))
            nextSteps.append(text(
                "稍后重试被限流的探测，并对照其他已成功的检查或正常网页访问。",
                "Retry rate-limited probes later and compare them with successful checks or ordinary web access."
            ))
        }
        if context.reachableEndpointCount > 0 {
            observations.append(text(
                "有 \(context.reachableEndpointCount) 个外部探测成功，说明这些探测点在本次检查中可达。",
                "\(context.reachableEndpointCount) external probes succeeded, so those tested endpoints were reachable in this snapshot."
            ))
        }
        if context.otherHTTPFailureCount > 0 {
            observations.append(text(
                "另有 \(context.otherHTTPFailureCount) 个探测收到非成功 HTTP 状态，不能据此直接认定节点或订阅失效。",
                "\(context.otherHTTPFailureCount) other probes returned unsuccessful HTTP statuses; those responses do not establish a node or subscription failure."
            ))
        }
        if context.transportFailureCount > 0 {
            observations.append(text(
                "有 \(context.transportFailureCount) 个外部探测未取得 HTTP 响应，仍需区分网络、路由和目标服务问题。",
                "\(context.transportFailureCount) external probes obtained no HTTP response; network, routing, and target-service issues still need to be distinguished."
            ))
            nextSteps.append(text(
                "对照其他探测和正常网页访问；若只有个别服务失败，先核对目标服务状态。",
                "Compare other probes and ordinary web access; if only particular services fail, check those services first."
            ))
        }

        if context.dnsFailureCount > 0 {
            observations.append(text(
                "有 \(context.dnsFailureCount)/\(context.dnsCheckCount) 个系统 DNS 查询失败；这里测试的是 macOS 解析路径，不能单独定位为 Mihomo DNS 故障。",
                "\(context.dnsFailureCount) of \(context.dnsCheckCount) system DNS lookups failed. These checks test the macOS resolver, not Mihomo DNS in isolation."
            ))
            nextSteps.append(text(
                "先复查系统 DNS 和当前网络，再对照 Nexora 的解析与路由配置。",
                "Recheck system DNS and the current network, then compare Nexora's resolver and routing configuration."
            ))
        }

        if context.systemTunnelDetected {
            if context.runtimeActive, context.tunEnabled {
                observations.append(text(
                    "Nexora 的 TUN 已启用，系统中也检测到隧道路由；这与当前模式相符，不能仅凭它认定有第二个 VPN。",
                    "Nexora TUN is enabled and a system tunnel route is present. This is consistent with the current mode and does not establish a second VPN."
                ))
            } else {
                observations.append(text(
                    "检测到系统隧道路由，而 Nexora 的 TUN 当前未接管连接。可能涉及其他 VPN，但这些检查不能证明它覆盖了 Nexora。",
                    "A system tunnel route is present while Nexora TUN is not active. Another VPN may be involved, but these checks do not prove it overrides Nexora."
                ))
                nextSteps.append(text(
                    "核对其他 VPN/TUN 的运行状态，一次只改变一个连接选项后重新检测。",
                    "Check other VPN/TUN apps and change only one connection setting at a time before retesting."
                ))
            }
        }

        if context.exitLookupFailed {
            observations.append(text(
                "本次未取得新出口地址；出口查询失败不等于所有互联网访问都失败。",
                "A fresh exit address was not obtained; an exit lookup failure does not mean all internet access failed."
            ))
        } else if context.runtimeActive, context.egress != .proxy, context.mode != .direct {
            observations.append(text(
                "出口显示未采用 Nexora 代理查询结果，仍不能由此确定全部应用的流量路径。",
                "The visible exit did not use Nexora's proxy lookup result; this does not identify the traffic path of every app."
            ))
        }

        if !context.runtimeActive {
            observations.append(text(
                "Nexora 当前未作为活动连接运行；TUN 开关若已启用，也可能只是下次连接的偏好。",
                "Nexora is not running as the active connection; an enabled TUN preference may only apply to the next connection."
            ))
        }
        if context.slowEndpointCount > 0 {
            observations.append(text(
                "有 \(context.slowEndpointCount) 个成功探测耗时超过 1.5 秒，仅说明这些探测当时较慢。",
                "\(context.slowEndpointCount) successful probes took over 1.5 seconds; this only shows those probes were slow at that time."
            ))
        }

        let hasProbes = context.listenerCheckCount + context.dnsCheckCount + context.endpointCheckCount > 0
        let summary: String
        if context.hasSystemProxyError {
            summary = text("先处理系统代理恢复错误，避免请求继续指向失效监听器。", "Address the system proxy restoration error first so requests are not left pointing at an unavailable listener.")
        } else if context.expectsCoreListeners, context.missingListenerCount > 0 {
            summary = text("本地核心监听不完整，是当前需要优先检查的环节。", "Expected local core listeners are missing; inspect that local runtime first.")
        } else if context.foreignListenerCount > 0 {
            summary = text("发现监听进程与当前核心不一致，需要先核对端口归属。", "Listener ownership differs from the current core; verify the port owners first.")
        } else if context.dnsFailureCount > 0 {
            summary = text("系统解析检查有失败，但尚不能确定故障位于哪一层。", "Some system DNS checks failed, but the failing layer is not yet established.")
        } else if context.transportFailureCount > 0 {
            summary = context.reachableEndpointCount > 0
                ? text("外部探测部分成功、部分失败，尚无证据表明全网中断。", "External probes have mixed results; a whole-network outage is not established.")
                : text("外部探测未全部完成，需要进一步区分连接路径与目标服务问题。", "External probes did not all complete; distinguish connection-path issues from target-service problems.")
        } else if context.rateLimitedEndpointCount > 0 {
            summary = text("部分检测服务正在限流，不能把 HTTP 429 当作 VPN 已断网。", "Some diagnostic services are rate limiting requests; HTTP 429 does not establish a VPN outage.")
        } else if context.otherHTTPFailureCount > 0 {
            summary = text("检测服务返回了错误状态，需要对照其他访问结果判断。", "Diagnostic services returned unsuccessful statuses; compare other access results before drawing a conclusion.")
        } else if !hasProbes {
            summary = text("诊断数据尚不完整，暂时无法判断网络状态。", "Diagnostic evidence is incomplete, so network status is not established yet.")
        } else if !context.runtimeActive {
            summary = text("Nexora 当前未接管连接，这些检查反映的是当前系统网络。", "Nexora is not the active connection; these checks describe the current system network.")
        } else if context.exitLookupFailed {
            summary = text("出口地址查询失败，需结合端口和外部探测判断连接情况。", "The exit lookup failed; use the listener and external probes to assess connectivity.")
        } else {
            summary = text("本次探测未发现明确的本地阻断证据，仍需以实际访问表现为准。", "These probes found no clear local blocking evidence; actual access still determines the user-visible result.")
        }
        if observations.isEmpty {
            observations.append(text("尚无足够探测证据支持具体故障判断。", "There is not enough probe evidence to identify a specific fault.") )
        }
        if !hasProbes {
            nextSteps.append(text("先运行网络诊断，再查看本次解释。", "Run a network diagnosis before reviewing an explanation.") )
        }
        if nextSteps.isEmpty {
            nextSteps.append(text("如果实际访问仍有问题，对照节点和出站模式后重新诊断。", "If access still fails, compare the selected node and outbound mode, then rerun the diagnosis.") )
        }
        nextSteps.append(text("网络状态变化后请重新诊断；本次结果只代表检测时刻。", "Rerun the diagnosis after network changes; these results describe only the time of the checks.") )
        return DiagnosticExplanation(summary: summary, observations: observations, nextSteps: nextSteps)
    }

    /// Stable, privacy-reviewed input for both the real model and test runners.
    public func modelPrompt(context: DiagnosticExplanationContext, language: AppLanguage) -> String {
        let explanation = ruleExplanation(context: context, language: language)
        let choices = summaryChoices(for: explanation, language: language)
        let encoded = (try? JSONEncoder().encode(choices)) ?? Data("[]".utf8)
        return """
        Arrange already verified diagnostic sentences for a concise summary.
        Return one to three distinct choices. Always include overview (index 0).
        overview=0, firstEvidence=1, limitation=2.
        Prefer the primary local fault before secondary probe limitations.
        Never supply new sentences, causes, network settings, or commands.
        The evidence has only allowlisted states and counts; it contains no raw user content.
        Evidence: \(context.sanitizedJSON)
        Verified sentences: \(String(decoding: encoded, as: UTF8.self))
        """
    }

    public func explain(context: DiagnosticExplanationContext, language: AppLanguage) async throws -> DiagnosticExplanation {
        try Task.checkCancellation()
        let fallback = ruleExplanation(context: context, language: language)
        let modelAvailability = availability()
        try Task.checkCancellation()
        guard modelAvailability == .available else { return fallback }
        do {
            let priorities = try await generateBeforeDeadline(prompt: modelPrompt(context: context, language: language))
            try Task.checkCancellation()
            guard !priorities.isEmpty, priorities.count <= 3, priorities.contains(0),
                  Set(priorities).count == priorities.count,
                  priorities.allSatisfy({ (0...2).contains($0) }) else { return fallback }
            let choices = summaryChoices(for: fallback, language: language)
            var seen: Set<String> = []
            let sentences = priorities.map { choices[$0] }.filter { seen.insert($0).inserted }
            return DiagnosticExplanation(
                summary: sentences.joined(separator: " "),
                observations: fallback.observations,
                nextSteps: fallback.nextSteps,
                source: .onDeviceModel
            )
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return fallback
        }
    }

    private func summaryChoices(for explanation: DiagnosticExplanation, language: AppLanguage) -> [String] {
        [
            explanation.summary,
            explanation.observations.first ?? explanation.summary,
            Self.usesChinese(language)
                ? "这些检查只覆盖当前快照，尚不能证明所有网站或应用都可用。"
                : "These checks cover only this snapshot and do not establish that every website or app is reachable.",
        ]
    }

    private static func usesChinese(_ language: AppLanguage) -> Bool {
        language.locale.language.languageCode?.identifier == "zh"
    }

    private static func systemAvailability() -> DiagnosticModelAvailability {
        guard #available(macOS 26.0, *) else { return .unsupportedSystem }
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible: return .deviceIneligible
            case .appleIntelligenceNotEnabled: return .intelligenceDisabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable
            }
        }
    }

    private static func generateSummaryOrder(_ prompt: String) async throws -> [Int] {
        guard #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable else {
            throw DiagnosticGenerationFailure.unavailable
        }
        // This exact model is Apple's on-device model. No tools, adapters,
        // Private Cloud Compute model, or third-party provider are supplied.
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: [],
            instructions: "Choose a concise ordering of supplied verified sentences. Do not infer or invent facts. Always include overview."
        )
        let response = try await session.respond(
            to: prompt,
            generating: DiagnosticSummaryOrder.self,
            options: GenerationOptions(temperature: 0, maximumResponseTokens: 128)
        )
        return response.content.priorities.map { choice in
            switch choice {
            case .overview: 0
            case .firstEvidence: 1
            case .limitation: 2
            }
        }
    }

    private func generateBeforeDeadline(prompt: String) async throws -> [Int] {
        let gate = DiagnosticGenerationGate()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let generation = Task {
                    do {
                        try Task.checkCancellation()
                        gate.finish(.success(try await generate(prompt)))
                    }
                    catch { gate.finish(.failure(error)) }
                }
                let timeout = Task {
                    do {
                        try await Task.sleep(for: maximumGenerationDuration)
                        gate.finish(.failure(DiagnosticGenerationFailure.timedOut))
                    } catch { }
                }
                gate.track([generation, timeout])
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

@available(macOS 26.0, *)
@Generable
private enum DiagnosticSummaryChoice {
    case overview
    case firstEvidence
    case limitation
}

@available(macOS 26.0, *)
@Generable
private struct DiagnosticSummaryOrder {
    @Guide(description: "One to three distinct choices; always include overview.", .count(1...3))
    var priorities: [DiagnosticSummaryChoice]
}

private enum DiagnosticGenerationFailure: Error {
    case unavailable
    case timedOut
}

/// A timeout/cancellation resumes the caller immediately, even if a model
/// implementation does not promptly cooperate with cancellation. Late results
/// are ignored, and the losing tasks receive cancellation.
private final class DiagnosticGenerationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Int], Error>?
    private var result: Result<[Int], Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<[Int], Error>) {
        lock.lock()
        let completed = result
        if completed == nil { self.continuation = continuation }
        lock.unlock()
        if let completed { continuation.resume(with: completed) }
    }

    func track(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        let completed = result != nil
        if !completed { self.tasks = tasks }
        lock.unlock()
        if completed { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<[Int], Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
