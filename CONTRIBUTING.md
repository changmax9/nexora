# Contributing

Nexora uses Swift Package Manager and targets macOS 15 or later.

Before opening a pull request:

```bash
swift test
swift build -c release
```

Keep runtime binaries, Geo data, private profiles, and local logs out of
commits. Use `./script/bootstrap.sh` to install local runtime dependencies.

Please keep UI changes keyboard-accessible, respect Reduce Motion, and add
tests for state or service behavior.
