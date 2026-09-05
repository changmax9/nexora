import Foundation

enum MenuBarProxyResolver {
    static func selectors(in groups: [ProxyGroup]) -> [ProxyGroup] {
        groups.filter { $0.kind == .selector || $0.kind == .unknown }
    }

    static func resolve(
        groups: [ProxyGroup],
        mode: OutboundMode,
        preferredName: String? = nil
    ) -> ProxyGroup? {
        let candidates = selectors(in: groups)
        if let preferredName, let preferred = candidates.first(where: { $0.name == preferredName }) {
            return preferred
        }
        let global = candidates.first { $0.name == "GLOBAL" }
        if mode == .global, let global { return global }
        // Follow the configured entry selector instead of a subscription-specific name.
        if let selected = global?.nodes.first(where: { $0.isSelected && $0.isGroup }),
           let entry = candidates.first(where: { $0.name == selected.name }) {
            return entry
        }
        return candidates.filter { $0.name != "GLOBAL" }.sorted {
            if $0.nodes.count != $1.nodes.count { return $0.nodes.count > $1.nodes.count }
            return $0.name < $1.name
        }.first ?? global
    }
}
