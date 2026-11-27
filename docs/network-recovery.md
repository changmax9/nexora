# Restoring network access after disconnect

Nexora restores macOS HTTP, HTTPS and SOCKS settings before stopping Mihomo.
A captured setting that points at Nexora's own listener is restored with that
protocol disabled, so a previous crash cannot turn a stopped listener back on.
Unrelated proxy endpoints retain their original settings.

Before enabling the system proxy, Nexora atomically saves the original settings
and network service to `system-proxy-recovery.json` in its Application Support
directory. On relaunch it restores this record before the user connects again.
The record is removed only after reading back and verifying all three protocols.
If cleanup fails, Disconnect and Quit retain the running core and report the
failure so cleanup can be retried.

The receipt also records Nexora's actual proxy endpoints and its owner process
identity. Recovery checks each protocol before restoring it, preserving proxy
settings taken over by another application. A second instance cannot recover
the live owner's receipt or launch a replacement core over that connection.
Old receipts remain readable and use the last runtime file's ports as a fallback.

The managed mixed, controller, and DNS listeners reserve distinct ports. Imported
HTTP/SOCKS listeners are disabled in the runtime copy because both system proxy
protocols use the managed mixed listener. The imported source file is preserved.

The build can be staged without interrupting an active connection:

```sh
BUILD_CONFIGURATION=debug ./script/build_and_run.sh --stage
```

A local installer can launch the installed app and request reconnection with:

```sh
open -n /Applications/Nexora.app --args --connect
```

This performs the same serialized connection action as Siri and runs locally,
without needing an active Codex conversation. It does not persist an automatic
connection preference.

`./script/install_and_reconnect.sh --check` verifies the staged bundle without
changing the running app. With `--apply`, it copies a backup and prepares the
replacement before quitting, installs the staged app, launches with `--connect`,
and checks that ChatGPT can be reached through the new proxy. This step briefly
reconnects the VPN and should be run when the user is ready for the switch.

Regression coverage is in `SystemProxyRecoveryTests`, `SystemProxySafetyTests`
and `RuntimeLifecycleRegressionTests`. These use simulated system settings and
isolated fake cores; they do not disconnect the host's active VPN.
