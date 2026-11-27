import Foundation
import Testing
import Yams
@testable import ClashGlassCore

@Suite("Configuration parsing regressions")
struct ConfigurationParsingRegressionTests {
    @Test func inlineCommentsDoNotBecomeRuntimeValues() throws {
        let settings = try MihomoConfigurationInspector.inspect(yaml: """
        mixed-port: 17890 # local listener
        external-controller: '127.0.0.1:19090' # controller
        secret: 'abc # inside secret' # controller authentication
        mode: global # default mode
        tun: {enable: true} # compact mapping
        dns: {listen: '[::]:15353'}
        """)
        #expect(settings.httpPort == 17890)
        #expect(settings.socksPort == 17890)
        #expect(settings.controllerHost == "127.0.0.1")
        #expect(settings.controllerPort == 19090)
        #expect(settings.secret == "abc # inside secret")
        #expect(settings.mode == .global)
        #expect(settings.tunEnabled)
        #expect(settings.dnsListenHost == "::")
        #expect(settings.dnsListenPort == 15353)
    }

    @Test func IPv6ControllerAddressKeepsItsCompleteHostAndPort() throws {
        let settings = try MihomoConfigurationInspector.inspect(yaml: "external-controller: '[::1]:19090'\n")
        #expect(settings.controllerHost == "::1")
        #expect(settings.controllerPort == 19090)
    }

    @Test(arguments: [-1, 65_536, Int.max])
    func invalidPortsFailWithoutCreatingAnInvalidAllocatorRange(port: Int) {
        #expect(throws: MihomoConfigurationInspectionError.invalidPort("mixed-port")) {
            try MihomoConfigurationInspector.inspect(yaml: "mixed-port: \(port)\n")
        }
        #expect(throws: RuntimeConfigurationError.noAvailablePort(port)) {
            try RuntimePortAllocator().availableTCPPort(host: "127.0.0.1", preferredPort: port)
        }
    }

    @Test(arguments: [
        "proxy-groups:\n- name: Proxy # primary selector\n  type: select\n  proxies: [DIRECT]\n",
        "proxy-groups: [{name: Proxy, type: select, proxies: [DIRECT]}]\n",
        "proxy-groups:\n  - {name: Proxy, type: select, proxies: [DIRECT]}\n",
    ])
    func selectorResolutionUsesYAMLStructure(yaml: String) {
        #expect(RoutingVPNTargetResolver.target(from: yaml) == "Proxy")
    }

    @Test(arguments: [
        "proxy-groups:\n- name: Proxy\n  type: select\n  proxies: [DIRECT]\nrules:\n- MATCH,DIRECT\n",
        "proxy-groups: [{name: Proxy, type: select, proxies: [DIRECT]}]\nrules: ['MATCH,DIRECT']\n",
        "{proxy-groups: [{name: Proxy, type: select, proxies: [DIRECT]}], rules: ['MATCH,DIRECT']}\n",
    ])
    func routingOverridesPreserveBlockAndFlowCollections(yaml: String) throws {
        let fixture = try ParsingFixture(yaml: yaml)
        defer { fixture.remove() }
        let prepared = try fixture.preparer.prepare(
            sourceURL: fixture.sourceURL,
            runtimeDirectoryURL: fixture.runtimeURL,
            routingOverrides: [
                RoutingOverride(domain: "openai.com", policy: .vpn),
                RoutingOverride(domain: "example.com", policy: .direct),
            ]
        )
        let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)
        let parsedDocument = try Yams.compose(yaml: runtime)
        let document = try #require(parsedDocument)
        #expect(document["rules"]?.array(of: String.self) == [
            "DOMAIN-SUFFIX,example.com,DIRECT",
            "DOMAIN-SUFFIX,openai.com,Proxy",
            "MATCH,DIRECT",
        ])
        #expect(RoutingVPNTargetResolver.target(from: runtime) == "Proxy")
        #expect(try String(contentsOf: fixture.sourceURL, encoding: .utf8) == yaml)
    }

    @Test func runtimeRewritingPreservesUnrelatedScalarValuesAndDNSOptions() throws {
        let yaml = """
        mixed-port: 17890 # listener
        external-controller: '[::1]:19090'
        secret: 'abc # secret' # comment
        mode: global # actual mode
        dns: {enable: true, listen: '[::]:15353', nameserver: ['https://1.1.1.1/dns-query']}
        proxy-groups: [{name: "Bob's Proxy", type: select, proxies: [DIRECT]}]
        rules: ['MATCH,DIRECT']
        """
        let fixture = try ParsingFixture(yaml: yaml)
        defer { fixture.remove() }
        let prepared = try fixture.preparer.prepare(
            sourceURL: fixture.sourceURL,
            runtimeDirectoryURL: fixture.runtimeURL,
            routingOverrides: [RoutingOverride(domain: "openai.com", policy: .vpn)]
        )
        let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)
        let parsedDocument = try Yams.compose(yaml: runtime)
        let document = try #require(parsedDocument)
        #expect(prepared.controllerSecret == "abc # secret")
        #expect(document["secret"]?.string == prepared.controllerSecret)
        #expect(document["mode"]?.string == "global")
        #expect(document["dns"]?["listen"]?.string == "127.0.0.1:15353")
        #expect(document["dns"]?["nameserver"]?.array(of: String.self) == ["https://1.1.1.1/dns-query"])
        #expect(document["rules"]?.array(of: String.self) == [
            "DOMAIN-SUFFIX,openai.com,Bob's Proxy", "MATCH,DIRECT",
        ])
    }

    @Test func legacyMisplacedPlusDNSPoliciesAreOmittedOnlyFromTheRuntime() throws {
        let yaml = """
        dns:
          enable: true
          nameserver: [1.1.1.1]
          nameserver-policy:
            '+.bilivideo.+': [9.9.9.9]
            '+.bilivideo.com': [223.5.5.5]
            'obsolete.+,+.example.com': [8.8.8.8]
            '+.example.com': [1.0.0.1]
            'geosite:category+literal': [223.6.6.6]
            '+': [192.0.2.53]
          proxy-server-nameserver-policy:
            '+.legacy.+': [9.9.9.9]
            '+.example.net': [1.1.1.1]
        x-extension: {'+.bilivideo.+': keep-this-value}
        rules: ['MATCH,DIRECT']
        """
        let fixture = try ParsingFixture(yaml: yaml)
        defer { fixture.remove() }
        let prepared = try fixture.preparer.prepare(sourceURL: fixture.sourceURL, runtimeDirectoryURL: fixture.runtimeURL)
        let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)
        let parsedRuntime = try Yams.compose(yaml: runtime)
        let document = try #require(parsedRuntime)
        let dns = try #require(document["dns"])
        let policy = try #require(dns["nameserver-policy"])
        #expect(policy["+.bilivideo.+"] == nil)
        #expect(policy["+.bilivideo.*"] == nil)
        #expect(policy["+.bilivideo.com"]?.array(of: String.self) == ["223.5.5.5"])
        #expect(policy["+.example.com"]?.array(of: String.self) == ["1.0.0.1"])
        #expect(policy["+.example.com,+.example.com"]?.array(of: String.self) == ["8.8.8.8"])
        #expect(policy["geosite:category+literal"]?.array(of: String.self) == ["223.6.6.6"])
        #expect(policy["+"]?.array(of: String.self) == ["192.0.2.53"])
        #expect(dns["proxy-server-nameserver-policy"]?["+.legacy.+"] == nil)
        #expect(dns["proxy-server-nameserver-policy"]?["+.example.net"]?.array(of: String.self) == ["1.1.1.1"])
        #expect(document["x-extension"]?["+.bilivideo.+"]?.string == "keep-this-value")
        #expect(try String(contentsOf: fixture.sourceURL, encoding: .utf8) == yaml)
    }

    @Test func validationUsesACompatibleCopyOnlyForLegacyDNSPolicies() throws {
        let yaml = """
        dns:
          nameserver-policy:
            '+.bilivideo.+': [9.9.9.9]
            '+.bilivideo.com': [1.1.1.1]
        rules: ['MATCH,DIRECT']
        """
        let fixture = try ParsingFixture(yaml: yaml)
        defer { fixture.remove() }
        let compatible = try fixture.preparer.validationConfiguration(yaml: yaml)
        let normalized = try #require(compatible)
        let parsedDocument = try Yams.compose(yaml: normalized)
        let document = try #require(parsedDocument)
        #expect(document["dns"]?["nameserver-policy"]?["+.bilivideo.+"] == nil)
        #expect(document["dns"]?["nameserver-policy"]?["+.bilivideo.com"]?.array(of: String.self) == ["1.1.1.1"])
        #expect(document["mixed-port"] == nil)
        #expect(document["external-controller"] == nil)
        #expect(try String(contentsOf: fixture.sourceURL, encoding: .utf8) == yaml)
        #expect(try fixture.preparer.validationConfiguration(yaml: normalized) == nil)
    }

    @Test(arguments: [
        "# formatting must stay unchanged\ndns: {nameserver-policy: {'+.bilivideo.com': [1.1.1.1]}}\n",
        "dns: {nameserver-policy: {'+': [1.1.1.1], 'geosite:category+literal': [8.8.8.8]}}\n",
        "mode: rule\nproxy-groups: []\nrules: ['MATCH,DIRECT']\n",
    ])
    func validationLeavesOrdinaryInputUntouched(yaml: String) throws {
        #expect(try RuntimeConfigurationPreparer().validationConfiguration(yaml: yaml) == nil)
    }

    @Test func inheritedLegacyDNSPolicyEntriesAreOmittedWithoutLosingValidDefaults() throws {
        let fixture = try ParsingFixture(yaml: """
        x-policy-defaults: &policy-defaults
          '+.legacy.+': [9.9.9.9]
          '+.example.com': [1.1.1.1]
        dns:
          nameserver-policy:
            <<: *policy-defaults
            '+.example.net': [8.8.8.8]
        rules: ['MATCH,DIRECT']
        """)
        defer { fixture.remove() }
        let prepared = try fixture.preparer.prepare(sourceURL: fixture.sourceURL, runtimeDirectoryURL: fixture.runtimeURL)
        let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)
        let parsedRuntime = try Yams.load(yaml: runtime) as? [String: Any]
        let document = try #require(parsedRuntime)
        let dns = try #require(document["dns"] as? [String: Any])
        let policies = try #require(dns["nameserver-policy"] as? [String: Any])
        #expect(policies["+.legacy.+"] == nil)
        #expect(policies["+.example.com"] as? [String] == ["1.1.1.1"])
        #expect(policies["+.example.net"] as? [String] == ["8.8.8.8"])
        let extensionDefaults = try #require(document["x-policy-defaults"] as? [String: Any])
        #expect(extensionDefaults["+.legacy.+"] as? [String] == ["9.9.9.9"])
    }

    @MainActor
    @Test func persistedIPv6ProfileInitializesTheControllerWithoutCrashing() async throws {
        let fixture = try ParsingFixture(yaml: """
        external-controller: '[::1]:19090' # IPv6 loopback controller
        secret: 'abc # secret' # authentication
        mode: global # configured mode
        proxy-groups: []
        rules: ['MATCH,DIRECT']
        """)
        defer { fixture.remove() }
        let repository = ManagedProfileRepository(rootURL: fixture.rootURL.appendingPathComponent("Managed"))
        let profile = try await repository.importProfile(from: fixture.sourceURL) { _ in .success }
        let suite = "Nexora.ConfigurationParsing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(profileRepository: repository, userDefaults: defaults)
        #expect(store.selectedManagedProfileID == profile.id)
        #expect(store.controllerURL.absoluteString == "http://[::1]:19090")
        #expect(store.controllerURL.port == 19090)
        #expect(store.controllerSecret == "abc # secret")
        #expect(store.selectedMode == .global)
        #expect(store.lastErrorMessage == nil)
    }

    @Test func anchorsMergeDefaultsAndUnknownFieldsKeepTheirMeaning() throws {
        let yaml = """
        x-runtime-defaults: &runtime-defaults
          mixed-port: 17890
          external-controller: '[::1]:19090'
          secret: 'merged # secret'
          mode: global
        <<: *runtime-defaults
        x-proxy-defaults: &proxy-defaults
          type: ss
          server: 192.0.2.1
          port: 443
          cipher: aes-128-gcm
          password: 'password # literal'
        proxies:
          - <<: *proxy-defaults
            name: Alpha
          - <<: [*proxy-defaults, {udp: true}]
            name: Beta
            server: 192.0.2.2
        x-selector-defaults: &selector-defaults
          type: select
          proxies: [Alpha, Beta]
        proxy-groups:
          - <<: *selector-defaults
            name: Proxy
        x-dns-defaults: &dns-defaults
          enable: true
          listen: '[::]:15353'
          nameserver: ['https://1.1.1.1/dns-query']
        dns: {<<: *dns-defaults, prefer-h3: true}
        x-extra:
          description: |+
            Preserve a multiline string.


          flags: {enabled: true, label: 'true', count: 7}
        rules: ['MATCH,DIRECT']
        """
        let fixture = try ParsingFixture(yaml: yaml)
        defer { fixture.remove() }
        let settings = try MihomoConfigurationInspector.inspect(yaml: yaml)
        #expect(settings.httpPort == 17890)
        #expect(settings.controllerHost == "::1")
        #expect(settings.controllerPort == 19090)
        #expect(settings.secret == "merged # secret")
        #expect(settings.mode == .global)
        #expect(settings.dnsListenPort == 15353)
        #expect(RoutingVPNTargetResolver.target(from: yaml) == "Proxy")
        let prepared = try fixture.preparer.prepare(
            sourceURL: fixture.sourceURL,
            runtimeDirectoryURL: fixture.runtimeURL,
            routingOverrides: [RoutingOverride(domain: "openai.com", policy: .vpn)]
        )
        let runtime = try String(contentsOf: prepared.configURL, encoding: .utf8)
        let parsedSource = try Yams.load(yaml: yaml) as? [String: Any]
        let parsedRuntime = try Yams.load(yaml: runtime) as? [String: Any]
        let sourceDocument = try #require(parsedSource)
        let runtimeDocument = try #require(parsedRuntime)
        for key in ["proxies", "proxy-groups", "x-extra", "x-proxy-defaults", "x-selector-defaults", "x-runtime-defaults"] {
            let sourceValue = try #require(sourceDocument[key])
            let runtimeValue = try #require(runtimeDocument[key])
            #expect(
                try JSONSerialization.data(withJSONObject: sourceValue, options: .sortedKeys)
                    == JSONSerialization.data(withJSONObject: runtimeValue, options: .sortedKeys)
            )
        }
        #expect(runtimeDocument["secret"] as? String == "merged # secret")
        #expect(runtimeDocument["mode"] as? String == "global")
        let dns = try #require(runtimeDocument["dns"] as? [String: Any])
        #expect(dns["listen"] as? String == "127.0.0.1:15353")
        #expect(dns["prefer-h3"] as? Bool == true)
        #expect(dns["nameserver"] as? [String] == ["https://1.1.1.1/dns-query"])
        #expect(runtimeDocument["rules"] as? [String] == ["DOMAIN-SUFFIX,openai.com,Proxy", "MATCH,DIRECT"])
        #expect(try String(contentsOf: fixture.sourceURL, encoding: .utf8) == yaml)
    }

}

private struct ParsingFixture {
    let rootURL: URL
    var sourceURL: URL { rootURL.appendingPathComponent("source.yaml") }
    var runtimeURL: URL { rootURL.appendingPathComponent("Runtime", isDirectory: true) }
    var preparer: RuntimeConfigurationPreparer {
        RuntimeConfigurationPreparer(
            geoDataSourceURL: rootURL.appendingPathComponent("GeoData", isDirectory: true),
            portAllocator: RuntimePortAllocator(
                isTCPPortAvailable: { _, _ in true },
                isUDPPortAvailable: { _, _ in true }
            )
        )
    }

    init(yaml: String) throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let geoDataURL = rootURL.appendingPathComponent("GeoData", isDirectory: true)
        try FileManager.default.createDirectory(at: geoDataURL, withIntermediateDirectories: true)
        try yaml.write(to: sourceURL, atomically: true, encoding: .utf8)
        for name in ["geoip.dat", "geosite.dat"] {
            try Data("fixture".utf8).write(to: geoDataURL.appendingPathComponent(name))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
