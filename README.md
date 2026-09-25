<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Nexora icon">
</p>

<h1 align="center">Nexora</h1>

<p align="center">
  A lightweight, native macOS client powered by <a href="https://github.com/MetaCubeX/mihomo">Mihomo</a>.
</p>

Nexora is written in SwiftUI for macOS. It manages local Mihomo profiles,
proxy groups, routing overrides, connections, logs, system proxy settings, and
TUN state through Mihomo's controller API.

> Nexora is an independent community project and is not affiliated with
> MetaCubeX.

## Highlights

- Native macOS interface with responsive Liquid Glass controls
- Direct Mihomo process lifecycle and controller API integration
- Local YAML profile import, validation, selection, rename, and removal
- Rule, Global, and Direct outbound modes
- Per-profile routing overrides
- Proxy latency testing, live traffic, connection, and log views
- Menu bar quick access
- Light, dark, and live system appearance modes
- English, Simplified Chinese, Traditional Chinese, Japanese, French, Russian,
  Spanish, and Portuguese interface support
- Signed in-app updates powered by Sparkle
- No bundled subscriptions, sample profiles, or telemetry

## Requirements

- macOS 15 or later
- Xcode 16 or a Swift 6 toolchain

## Build

Download the current Mihomo core and Geo data:

```bash
./script/bootstrap.sh
```

Build and launch the app:

```bash
./script/build_and_run.sh
```

The downloaded runtime files stay local and are excluded from Git.

## Test

```bash
swift test
```

## Publish an update

Build the community DMG locally with an Apple signing identity. This keeps the
app, Mihomo, and the TUN helper signed by the same team:

```bash
CODE_SIGN_IDENTITY="Apple Development: ..." ./script/package_release.sh 0.2.0 --community
```

Stage that exact DMG and a source archive in a draft GitHub Release at a tag
pointing to the matching source commit. Run the manual Release workflow with
the version number; it verifies the DMG, signs it with Sparkle's EdDSA key,
uploads the appcast, and publishes the release. Installed copies show an
**Update** capsule beside the macOS window controls when a newer release is
available.

The `SPARKLE_PRIVATE_KEY` repository secret must remain configured. GitHub also
adds source code archives to each release automatically. The version number
determines an increasing build number so Sparkle can recognize updates from
locally installed builds.
Application preferences stay in `~/Library/Preferences`, while profiles and runtime data
stay in `~/Library/Application Support/Nexora`; replacing the app bundle
does not remove either location.

Community releases use Apple Development signing and are not notarized. macOS
requires the user to allow the app manually in Privacy & Security. TUN also
requires administrator approval in Login Items & Extensions. TUN has been
verified on the development Mac, but installation on another Mac is not yet
verified. Sparkle's EdDSA signature verifies that updates were produced with
the project's private key. See [TUN service](docs/tun-service.md) for details.

## Project layout

- `Sources/ClashGlass` — macOS application entry point and menu bar host
- `Sources/ClashGlassCore` — UI, state, Mihomo services, and repositories
- `Tests/ClashGlassTests` — unit and integration-oriented tests
- `script` — runtime bootstrap and local app bundle scripts

## License

Nexora is available under the MIT License. Mihomo and Geo data retain
their respective upstream licenses; see [NOTICE.md](NOTICE.md).
