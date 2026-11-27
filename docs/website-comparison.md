# Website connection comparison

Open **Diagnostics → Website connection comparison**, enter an HTTP(S) URL
(a bare hostname defaults to HTTPS), then select Compare or press Return.
The direct request and current Nexora route run concurrently. Cancel terminates
only the test requests. A stopped core is not started automatically.

The direct route bypasses system proxy settings and curl proxy environment/config
settings. Via Nexora explicitly uses the current local mixed listener and follows
the current mode and rules; a DIRECT rule can therefore make both routes direct.
TUN controls ingress and routing while Rule/Global/Direct remains an independent
setting; see [Mihomo running modes](https://wiki.metacubex.one/config/general/)
and [TUN configuration](https://wiki.metacubex.one/config/inbound/tun/).
When a system tunnel is active, the UI explains that direct requests can still
enter it and cannot represent turning the VPN off.

Results distinguish an HTTP response from DNS, connect, certificate/handshake,
timeout, proxy authentication and inactive-core failures. HTTP 403/404/5xx is
shown as a received response with an access/site-status hint. This does not test
browser cookies, login or full application behavior. HEAD is used first; 405/501
falls back to a bounded GET with the remaining request budget and a body limit.
TLS verification is always enabled, redirects stay within HTTP(S), and each route
has an eight-second budget (with a short minimum for a HEAD fallback).

Input and results are held only in memory. URLs with embedded user/password
credentials are rejected. No browser cookie jar is used; query strings are
removed from copied reports. Mode, node, TUN or other network-context changes
invalidate the result and discard old in-flight responses.

`WebsiteComparisonTests` covers routing arguments, URL validation, HTTP/transport
classification, concurrency, bounded fallback, cancellation/process cleanup,
stale responses, tunnel copy and localization. Optional real public-site checks:

```sh
NEXORA_WEBSITE_LIVE_PROXY_PORT=<current-mixed-port> swift test --filter liveWebsiteComparisonWhenExplicitlyRequested
```

These real checks make direct and proxied requests but do not toggle the host's
proxy, mode, node selection or TUN state.

Local verification on 2026-11-11 with TUN off: Baidu returned HTTP 200 on both
routes; ChatGPT direct timed out while the explicit Nexora route returned HTTP
200. The live test exercised this service implementation, not a separate curl
command reproducing its behavior.

The installed native UI was also checked for invalid input, Return submission,
successful direct/current-rule results and direct timeout results. The complete
suite including the menu-bar editing follow-up passes 323 tests.
