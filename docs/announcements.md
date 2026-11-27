# Broadcast Announcements

Nexora supports remote broadcast announcements rendered inside the desktop app as a large Liquid Glass modal dialog (`AnnouncementModalOverlay`).

## Architecture

- **Feed branch**: `announcements` (an orphan branch in `changmax9/nexora` containing `current.json` so publishing announcements never modifies `main` or triggers app CI).
- **Client fetch URLs** (tried in order):
  1. `https://raw.githubusercontent.com/changmax9/nexora/announcements/current.json`
  2. `https://api.github.com/repos/changmax9/nexora/contents/current.json?ref=announcements`
- **Refresh policy**:
  - Fetches asynchronously at app launch, when VPN connects (`isStarted` transitions to `true`), and after system wake.
  - Enforces a 30-minute cooldown after a successful fetch; transient network errors leave the cooldown unset so connecting later retries immediately without surfacing error alerts.
  - Keeps dismissed announcement IDs in `UserDefaults` (`nexora.announcementDismissals.v1`, capped at 50 entries).
  - Supports re-opening the active announcement from **Settings → About → Announcement**.

## JSON Schema (`schemaVersion: 1`)

```json
{
  "schemaVersion": 1,
  "announcement": {
    "id": "20261127-notice",
    "kind": "notice",
    "title": "版本与节点使用提醒",
    "body": "公告正文内容...",
    "badge": "官方公告",
    "publishedAt": "2026-11-27T14:30:00Z",
    "startsAt": "2026-11-27T14:00:00Z",
    "expiresAt": "2026-12-05T16:00:00Z",
    "minVersion": "1.0.0",
    "maxVersion": "1.2.0",
    "displayPolicy": "once",
    "actionTitle": "查看详情",
    "actionURL": "https://github.com/changmax9/nexora/releases",
    "localizations": {
      "en": {
        "title": "Service Notice",
        "body": "Announcement body in English.",
        "badge": "Announcement",
        "actionTitle": "Learn More"
      }
    }
  }
}
```

- `kind`: `notice` | `update` | `warning` | `maintenance` (unknown values fall back to `notice`).
- `displayPolicy`: `once` (show once per `id`) | `daily` (show at most once per calendar day while active).
- `actionURL`: optional `https://` URL with no embedded credentials; non-HTTPS or credentialed URLs are ignored.
- Maximum payload size: `65,536` bytes (64 KiB).
- To withdraw an active announcement, publish `{"schemaVersion": 1, "announcement": null}`.

## Publishing with `script/announce.py`

Requires an authenticated `gh` CLI with push access to `changmax9/nexora`.

```bash
# Publish a notice (creates the orphan `announcements` branch automatically on first use)
./script/announce.py publish \
  --title "节点维护通知" \
  --body "今晚将优化部分线路，如遇到波动请尝试重新测速或切换节点。" \
  --kind notice \
  --display-policy once

# Inspect the live published announcement
./script/announce.py status

# Withdraw the current announcement
./script/announce.py clear
```

## Local Preview Without Publishing

Generate a sample file with `--dry-run --output` and pass `NEXORA_ANNOUNCEMENT_FILE` when launching the app:

```bash
./script/announce.py publish \
  --title "测试公告" \
  --body "这是一条本地预览的 Liquid Glass 公告弹窗。" \
  --dry-run --output /tmp/announcement.json

NEXORA_ANNOUNCEMENT_FILE=/tmp/announcement.json open -n /Applications/Nexora.app
```
