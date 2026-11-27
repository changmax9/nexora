# Agent Instructions for Nexora

## Broadcasting User Announcements

When the maintainer asks to publish, update, inspect, or withdraw a user-facing announcement in Nexora (from Codex, Antigravity, Claude Code, or any other AI coding tool), use `./script/announce.py` instead of editing `main` or creating app releases:

1. **Publish an announcement** (pass `--title-en` / `--body-en` if English localization is helpful, `--kind` in `notice|update|warning|maintenance`, and `--display-policy` `once` or `daily`):
   ```bash
   ./script/announce.py publish \
     --title "<标题>" \
     --body "<正文内容>" \
     --kind notice \
     --display-policy once
   ```
   Optional flags:
   - `--badge`, `--title-en`, `--body-en`, `--badge-en`
   - `--action-title`, `--action-title-en`, `--action-url` (strictly `https://`, no credentials)
   - `--starts-at`, `--expires-at` (ISO-8601)
   - `--min-version`, `--max-version`
   - `--id` (unique identifier; omit to auto-generate a timestamped ID)

2. **Check the currently published announcement**:
   ```bash
   ./script/announce.py status
   ```

3. **Withdraw / clear the active announcement**:
   ```bash
   ./script/announce.py clear
   ```

4. **Dry-run / local preview** (does not touch GitHub):
   ```bash
   ./script/announce.py publish --title "<标题>" --body "<正文>" --dry-run
   ```

Notes:
- `./script/announce.py` writes only `current.json` on the orphan `announcements` branch via `gh api` and never modifies the current local Git branch or working tree.
- Never include subscription credentials, tokens, or local user data in announcement payloads.
