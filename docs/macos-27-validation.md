# macOS 27 compatibility audit — 2026-09-15

## Environment

- Local OS: macOS 27.0, build 26A428.
- Toolchain: Xcode 26.6, macOS SDK 26.5. No Xcode 27 installation was available.
- Installed application: `/Applications/Nexora.app`, version 0.1.5.
- Previous bundle backed up to `/tmp/nexora-macos27-backup/Nexora.app`.

## Changes

- Present the menu panel without activating the main application; use a nonactivating panel that can join full-screen Spaces.
- Align connection headers and data with matching column allocation.
- Use a darker success green in light appearance for readable status and latency text.
- Label dashboard and Reduce Motion controls for accessibility and expose their selected state.
- Give diagnostic port rows identities that include their role: HTTP and SOCKS can share a port without SwiftUI reusing the wrong row.
- Display port numbers without locale-dependent thousands separators.

## Verification

- Reviewed Dashboard, Proxies, Routing, Profiles, Connections, Settings, and Diagnostics on the local macOS 27 system.
- Inspected regular and full-screen windows and light/dark appearances.
- Opened the panel over Nexora's full-screen window; exercised search, clear, Escape dismissal, and latency refresh.
- Validated the existing managed configuration successfully.
- Observed runtime restart recovery, live traffic and connection data, and successful DNS and external endpoint diagnostics.
- Reproduced duplicate diagnostic identities with a failing regression test before changing the identity implementation.
- Ran the full Swift test suite (146 tests), explicit `swift build`, bundle staging, installation, and strict deep signature verification.
- Used clean builds after observed incremental-build output did not match the edited source in UI checks.

## Limits

This is a compatibility audit on one macOS 27 build, not a claim that every possible defect is eliminated or that the app adopts new macOS 27-only APIs. The build uses SDK 26.5.

Other applications' full-screen Spaces, multiple displays, sleep/wake, TUN privilege flows, destructive connection actions, profile deletion, and Sparkle update delivery were not verified end-to-end. Existing automated tests cover additional runtime, configuration, routing, and lifecycle cases; they do not replace those manual integration checks.

## 2026-09-16 update — 0.1.6

The installed toolchain is now Xcode 27.0 (27A266a), macOS SDK 27.0, superseding the toolchain limitation above. Explicit `swift build` passed with this SDK. The full suite passed 156 tests before packaging.

Added a signed privileged TUN service and configuration/lifecycle regression coverage; see `tun-service.md` for its boundary and remaining live checks. TUN has not yet been enabled for live network testing.

Language selection, latency URL input, and timeout adjustment now use native glass surfaces. Verified the installed 0.1.6 Settings screen in dark appearance, opened the language menu, and changed timeout from 5,000 to 5,500 ms and back. Moved the language glass modifier outside the native menu label after visual testing showed that menu styling discarded the label background. Active switches inherit the selected accent color.

Staged with `--stage`, installed in `/Applications/Nexora.app`, relaunched, and confirmed version 0.1.6 in the UI. Strict deep bundle verification and explicit helper/Mihomo signing requirements passed. The `--verify` script mode was not used for this final stage; installed-app launch was verified directly. Previous bundle: `/tmp/Nexora-before-TUN-0.1.6.app`.

Final follow-up: rebuilt all sources and ran 156 tests successfully using a fresh scratch build directory and temporary user home. Reused the existing checksum-recorded Sparkle artifact after its network download stalled; source products were built afresh. Explicit final `swift build` and installed helper/core signature checks also passed.

Live registration exposed two approval-path defects, now fixed: an initial `notFound` status must attempt registration, and a registration error must still route to approval when the resulting status is `requiresApproval`. The installed build now registers successfully and reaches the macOS Touch ID/password approval sheet. Administrator authentication and live TUN connectivity remain pending; user consent to perform these checks was received.

After administrator approval, the daemon launched as root. Fixed helper executable discovery to use `Bundle.main.executableURL`: launchd's `BundleProgram` supplies a relative argv[0], which previously resolved Mihomo against the wrong directory. The fixed helper launched the bundled, signature-verified Mihomo successfully.

Live TUN creation was initially blocked by an existing FlClash TUN route on utun6. Mihomo's authenticated log endpoint reported `Start TUN listening error: configure tun interface: add route: 1.0.0.0/8: file exists`; the configuration endpoint confirmed `tun.enable = false`. An HTTP 200 received while that other tunnel was active is not proof of Nexora TUN connectivity. Added a specific route-conflict message sourced from helper logs, with regression coverage. After the user authorized the switch, disabling FlClash allowed Nexora to create its own tunnel.

With user permission, disabled FlClash TUN. Nexora then created utun6 and reported TUN enabled. DNS hijacking returned a fake-IP response, but direct HTTPS (explicitly bypassing HTTP proxies) timed out under Mixed; HTTP through Nexora's explicit proxy succeeded. Changing the live TUN stack to gVisor made the same direct HTTPS request return 200. Changed normalized TUN configuration to gVisor and added its regression assertion. All 157 tests and explicit `swift build` pass. Packaged and installed the update; final helper reload and post-restart connectivity validation completed after macOS authentication.

## Crash fix — 2026-09-16 20:50

Crash report `Nexora-2026-09-16-205032.ips` identifies SIGTRAP at `_dispatch_assert_queue_fail`, through `PrivilegedTUNService.request`'s NSXPC error callback. A callback inherited MainActor isolation although NSXPC invokes it on a background queue. Marked the error handler explicitly Sendable, and marked all helper protocol reply closures Sendable. Added a regression using a real NSXPCConnection to a nonexistent Mach service; its background error reply now completes without a crash. All 158 tests, explicit `swift build`, signed staging and strict installed bundle verification passed. This fixes the observed crash path; it does not imply every possible crash has been eliminated.

## Release audit — 0.1.6

Confirmed a subsequent live run using gVisor with TUN enabled on utun7. HTTPS requests explicitly bypassing HTTP proxies succeeded against Apple (200) and Google's connectivity endpoint (204). Reviewed the XPC crash fix, helper identity, callback isolation, configuration boundary, and packaging. Added a required Apple signing identity to release packaging; ad-hoc CI packages cannot authorize TUN. Added local DMG mode and certificate import/cleanup to release automation.

Built an optimized arm64 0.1.6 (build 16) local test DMG with Apple Development signing. Verified its checksum, mounted it read-only, verified the enclosed app's strict deep signature and helper identifier/team requirement, checked its version and executable architecture, and detached it. This artifact is not notarized and is not an Intel build. After unlocking, relaunched the installed release build, opened Settings, verified the glass controls, started TUN, confirmed Apple 200 and Google 204 through the tunnel, then disabled TUN and confirmed ordinary proxy traffic recovered.
