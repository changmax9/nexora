import Foundation

enum ProxySelectionResolver {
    static func selectedLeafNodeName(
        selectedGroupName: String,
        groups: [ProxyGroup]
    ) -> String? {
        var currentGroupName = selectedGroupName
        var visitedGroupNames = Set<String>()

        while visitedGroupNames.insert(currentGroupName).inserted {
            guard let group = groups.first(where: { $0.name == currentGroupName }),
                  let selectedNode = group.nodes.first(where: \.isSelected) else {
                return nil
            }
            guard selectedNode.isGroup else {
                return selectedNode.name
            }
            currentGroupName = selectedNode.name
        }

        return nil
    }

    static func targetGroups(
        selectedGroupName: String,
        nodeName: String,
        groups: [ProxyGroup]
    ) -> [String] {
        guard let selectedGroup = groups.first(where: { $0.name == selectedGroupName }) else {
            return []
        }
        if selectedGroup.kind.isAutomatic {
            return preferredParentSelector(
                selectedGroupName: selectedGroupName,
                nodeName: nodeName,
                groups: groups
            ).map { [$0] } ?? []
        }
        guard selectedGroup.kind == .selector || selectedGroup.kind == .unknown else {
            return []
        }
        guard selectedGroup.name == "GLOBAL" else {
            return [selectedGroup.name]
        }
        let preferred = groups
            .filter { candidate in
                candidate.name != "GLOBAL"
                    && candidate.kind == .selector
                    && candidate.nodes.contains(where: { $0.name == nodeName })
            }
            .min { lhs, rhs in
                lhs.nodes.count < rhs.nodes.count
            }?
            .name
        return [selectedGroup.name, preferred].compactMap { $0 }
    }

    static func targetGroup(
        selectedGroupName: String,
        nodeName: String,
        groups: [ProxyGroup]
    ) -> String? {
        targetGroups(
            selectedGroupName: selectedGroupName,
            nodeName: nodeName,
            groups: groups
        ).last
    }

    private static func preferredParentSelector(
        selectedGroupName: String,
        nodeName: String,
        groups: [ProxyGroup]
    ) -> String? {
        groups
            .filter { candidate in
                candidate.kind == .selector
                    && candidate.nodes.contains(where: { $0.name == selectedGroupName })
                    && candidate.nodes.contains(where: { $0.name == nodeName })
            }
            .min { lhs, rhs in
                if lhs.nodes.count == rhs.nodes.count {
                    return lhs.name != "GLOBAL" && rhs.name == "GLOBAL"
                }
                return lhs.nodes.count < rhs.nodes.count
            }?
            .name
    }
}

enum LatencyTestTargetResolver {
    static func testURL(
        nodeName: String,
        groups: [ProxyGroup],
        settings: LatencyTestSettings = LatencyTestSettings()
    ) -> String {
        groups.first(where: { group in
            group.kind.isAutomatic
                && group.testURL.flatMap(LatencyTestSettings.validTestURL) != nil
                && group.nodes.contains(where: { $0.name == nodeName })
        })?.testURL.flatMap(LatencyTestSettings.validTestURL)
            ?? groups.first(where: { group in
                group.testURL.flatMap(LatencyTestSettings.validTestURL) != nil
                    && group.nodes.contains(where: { $0.name == nodeName })
            })?.testURL.flatMap(LatencyTestSettings.validTestURL)
            ?? settings.testURL
    }
}

public enum LatencyTestPlan {
    public static let maximumConcurrentGroupTests = 2
    public static let maximumConcurrentFallbackTests = 8
    public static let defaultTestURL = "http://www.gstatic.com/generate_204"
    public static let defaultTimeoutMilliseconds = 5_000
}

struct LatencyTestSettings: Equatable, Sendable {
    static let minimumTimeoutMilliseconds = 500
    static let maximumTimeoutMilliseconds = 30_000

    let testURL: String
    let timeoutMilliseconds: Int

    init(
        testURL: String = LatencyTestPlan.defaultTestURL,
        timeoutMilliseconds: Int = LatencyTestPlan.defaultTimeoutMilliseconds
    ) {
        self.testURL = Self.normalizedTestURL(testURL)
        self.timeoutMilliseconds = Self.normalizedTimeoutMilliseconds(timeoutMilliseconds)
    }

    static func normalizedTestURL(_ value: String) -> String {
        validTestURL(value) ?? LatencyTestPlan.defaultTestURL
    }

    static func validTestURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    static func normalizedTimeoutMilliseconds(_ value: Int) -> Int {
        min(max(value, minimumTimeoutMilliseconds), maximumTimeoutMilliseconds)
    }

    static func validMeasuredDelay(_ value: Int?) -> Int? {
        guard let value,
              (1...maximumTimeoutMilliseconds).contains(value) else {
            return nil
        }
        return value
    }
}

struct LatencyGroupTest: Equatable, Sendable {
    let groupName: String
    let url: String
    let nodeNames: Set<String>

    func fallbackTests(excluding measuredNodeNames: Set<String>) -> [LatencyProxyTest] {
        nodeNames
            .subtracting(measuredNodeNames)
            .sorted()
            .map { LatencyProxyTest(proxyName: $0, url: url) }
    }
}

struct LatencyProxyTest: Equatable, Sendable {
    let proxyName: String
    let url: String
}

struct LatencyTestBatchPlan: Equatable, Sendable {
    let groupTests: [LatencyGroupTest]
    let fallbackTests: [LatencyProxyTest]

    var nodeNames: Set<String> {
        groupTests.reduce(into: Set<String>()) { result, test in
            result.formUnion(test.nodeNames)
        }.union(fallbackTests.map(\.proxyName))
    }
}

enum LatencyTestPlanner {
    static func plan(
        groups: [ProxyGroup],
        settings: LatencyTestSettings = LatencyTestSettings()
    ) -> LatencyTestBatchPlan {
        let automaticCandidates = groups
            .filter { $0.kind.isAutomatic }
            .map { group in
                LatencyGroupTest(
                    groupName: group.name,
                    url: group.testURL.flatMap(LatencyTestSettings.validTestURL)
                        ?? settings.testURL,
                    nodeNames: Set(
                        group.nodes
                            .filter(isLatencyTestable)
                            .map(\.name)
                    )
                )
            }
            .filter { !$0.nodeNames.isEmpty }
            .sorted { lhs, rhs in
                if lhs.nodeNames.count == rhs.nodeNames.count {
                    return lhs.groupName < rhs.groupName
                }
                return lhs.nodeNames.count > rhs.nodeNames.count
            }

        var covered = Set<String>()
        var groupTests: [LatencyGroupTest] = []
        for candidate in automaticCandidates
        where !candidate.nodeNames.subtracting(covered).isEmpty {
            groupTests.append(candidate)
            covered.formUnion(candidate.nodeNames)
        }

        let allConcreteNames = Set(
            groups.flatMap { group in
                group.nodes.filter(isLatencyTestable).map(\.name)
            }
        )
        let fallbackTests = allConcreteNames
            .subtracting(covered)
            .sorted()
            .map { nodeName in
                LatencyProxyTest(
                    proxyName: nodeName,
                    url: LatencyTestTargetResolver.testURL(
                        nodeName: nodeName,
                        groups: groups,
                        settings: settings
                    )
                )
            }
        return LatencyTestBatchPlan(
            groupTests: groupTests,
            fallbackTests: fallbackTests
        )
    }

    private static func isLatencyTestable(_ node: ProxyNode) -> Bool {
        guard !node.isGroup else {
            return false
        }
        return !["DIRECT", "REJECT", "PASS", "COMPATIBLE"]
            .contains(node.name.uppercased())
    }
}

struct LatencyTestProgress: Equatable, Sendable {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else {
            return 0
        }
        return min(1, Double(completed) / Double(total))
    }

    var text: String {
        "Testing \(completed)/\(total)"
    }
}
