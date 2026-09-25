# TUN service

Nexora 0.1.6 includes a signed SMAppService launch daemon for running bundled Mihomo with TUN privileges. The ordinary proxy process continues to run without elevated privileges.

## Local installation

Build with `APP_VERSION=0.1.6 CODE_SIGN_IDENTITY=<Apple signing identity> ./script/build_and_run.sh --stage`, then install `dist/Nexora.app` in Applications. Ad-hoc builds cannot authorize the service. The application, helper and Mihomo must share an Apple signing team. Sign nested executables before signing the bundle; do not use deep signing, which overwrites the helper's required identifier.

Enabling TUN registers the service. macOS may require approval in System Settings → General → Login Items & Extensions. After approval, enable TUN again. The service creates a virtual network interface and changes routing; only perform live verification with the user's authorization.

## Boundary and lifecycle

- The app and helper verify each other's signing identity; the helper separately verifies bundled Mihomo.
- The XPC interface accepts configuration bytes, not arbitrary executable paths, commands, or process IDs.
- Configuration is normalized to a loopback controller with a generated secret, LAN access disabled, and a private runtime directory.
- File providers, escaping provider paths, and certificate file references are rejected. HTTP providers use private cache paths. Inline certificate material remains supported.
- A session owns its process. App disconnection or helper termination stops that process and removes its private directory.
- Approval failure keeps the existing runtime. Failed TUN startup attempts to restore the previous ordinary runtime.

## Verification status

Configuration boundary and lifecycle regression tests pass, including denied approval, failed privileged startup, and return to an ordinary process. Installed application/helper/core signatures were verified. SMAppService approval, virtual interface creation, DNS/routing, and external connectivity have been tested on this Mac. This local Apple Development signed build is not a notarized distribution release.

Live follow-up: macOS approval and signed root-helper/core launch are verified. Resolve the helper using the executable bundle URL, not argv[0], because launchd supplies a relative BundleProgram. With FlClash's TUN disabled, gVisor mode created utun6 and direct Apple/Google HTTPS checks succeeded. Runtime errors now identify an existing TUN route conflict rather than only reporting that TUN was not enabled.

## Packaging

For a local Apple Development signed test image, run `CODE_SIGN_IDENTITY=<identity> APP_BUILD=<increasing build number> ./script/package_release.sh 0.1.6 --local`. This creates a DMG with an Applications shortcut, verifies its checksum, and disables automatic updates. It does not generate an appcast or claim notarization. The current local artifact is arm64 (Apple Silicon).

Community packaging uses a local Apple Development identity and rejects ad-hoc signing because the TUN trust boundary requires an Apple signing team. The prebuilt DMG is uploaded to a draft GitHub Release. The manual Release workflow uses the repository's `SPARKLE_PRIVATE_KEY` secret to sign that exact DMG for updates and publish the appcast. Apple Development signing does not satisfy Gatekeeper's normal public distribution policy: users must manually allow the app in Privacy & Security, and TUN requires administrator approval. The TUN installation flow has not been checked on another Mac. A notarized distribution additionally requires Developer ID signing, hardened runtime, notarization submission, and stapling.
