#!/usr/bin/env python3
"""Publish, inspect, or clear Nexora broadcast announcements without touching local Git state."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

DEFAULT_REPO = "changmax9/nexora"
DEFAULT_BRANCH = "announcements"
FEED_PATH = "current.json"
MAX_PAYLOAD_BYTES = 65_536
VALID_KINDS = ("notice", "update", "warning", "maintenance")
VALID_DISPLAY_POLICIES = ("once", "daily")
VERSION_RE = re.compile(r"^[vV]?[0-9]+(?:\.[0-9]+)*$")


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_iso_datetime(raw: str, flag_name: str) -> datetime:
    text = raw.strip()
    if not text:
        fail(f"{flag_name} must not be empty.")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        text = f"{text}T00:00:00+00:00"
    elif text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as exc:
        fail(f"invalid ISO-8601 date for {flag_name}: {raw} ({exc})")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def format_utc_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_action_url(raw: str) -> str:
    trimmed = raw.strip()
    if not trimmed or any(ch.isspace() for ch in trimmed):
        fail("--action-url must be a valid https:// URL without whitespace.")
    parsed = urlparse(trimmed)
    if parsed.scheme.lower() != "https" or not parsed.netloc or not parsed.hostname:
        fail("--action-url must use https:// with a valid host.")
    if parsed.username is not None or parsed.password is not None:
        fail("--action-url must not embed credentials.")
    return trimmed


def validate_version(raw: str, flag_name: str) -> str:
    trimmed = raw.strip()
    if not VERSION_RE.match(trimmed):
        fail(f"{flag_name} must look like 1.0.1 (got: {raw}).")
    return trimmed


def slugify_id(title: str, now_utc: datetime) -> str:
    digest = hashlib.sha256(f"{now_utc.isoformat()}:{title}".encode("utf-8")).hexdigest()[:8]
    ascii_slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:24]
    prefix = now_utc.strftime("%Y%m%d-%H%M%S")
    return f"{prefix}-{ascii_slug}-{digest}" if ascii_slug else f"{prefix}-{digest}"


def build_publish_envelope(args: argparse.Namespace) -> dict[str, Any]:
    title = args.title.strip()
    if not title:
        fail("--title must not be empty.")

    if args.body is not None and args.body_file is not None:
        fail("pass either --body or --body-file, not both.")
    if args.body_file is not None:
        body = Path(args.body_file).read_text(encoding="utf-8").strip()
    elif args.body is not None:
        body = args.body.strip()
    else:
        fail("either --body or --body-file is required.")
    if not body:
        fail("announcement body must not be empty.")

    now_utc = datetime.now(timezone.utc)
    announcement_id = (args.id or slugify_id(title, now_utc)).strip()
    if not announcement_id:
        fail("--id must not be empty.")

    starts_dt = parse_iso_datetime(args.starts_at, "--starts-at") if args.starts_at else None
    expires_dt = parse_iso_datetime(args.expires_at, "--expires-at") if args.expires_at else None
    if starts_dt and expires_dt and starts_dt > expires_dt:
        fail("--starts-at must be earlier than or equal to --expires-at.")

    announcement: dict[str, Any] = {
        "id": announcement_id,
        "kind": args.kind,
        "title": title,
        "body": body,
        "publishedAt": format_utc_iso(now_utc),
        "displayPolicy": args.display_policy,
    }
    if args.badge and args.badge.strip():
        announcement["badge"] = args.badge.strip()
    if starts_dt:
        announcement["startsAt"] = format_utc_iso(starts_dt)
    if expires_dt:
        announcement["expiresAt"] = format_utc_iso(expires_dt)
    if args.min_version:
        announcement["minVersion"] = validate_version(args.min_version, "--min-version")
    if args.max_version:
        announcement["maxVersion"] = validate_version(args.max_version, "--max-version")
    if args.action_title and args.action_title.strip():
        if not args.action_url:
            fail("--action-title requires --action-url.")
        announcement["actionTitle"] = args.action_title.strip()
    if args.action_url:
        announcement["actionURL"] = validate_action_url(args.action_url)

    en_loc: dict[str, str] = {}
    if args.title_en and args.title_en.strip():
        en_loc["title"] = args.title_en.strip()
    if args.body_en and args.body_en.strip():
        en_loc["body"] = args.body_en.strip()
    if args.badge_en and args.badge_en.strip():
        en_loc["badge"] = args.badge_en.strip()
    if args.action_title_en and args.action_title_en.strip():
        en_loc["actionTitle"] = args.action_title_en.strip()
    if en_loc:
        announcement["localizations"] = {"en": en_loc}

    return {"schemaVersion": 1, "announcement": announcement}


def serialize_envelope(envelope: dict[str, Any]) -> bytes:
    encoded = (json.dumps(envelope, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(encoded) > MAX_PAYLOAD_BYTES:
        fail(f"serialized announcement ({len(encoded)} bytes) exceeds {MAX_PAYLOAD_BYTES} bytes.")
    return encoded


def run_gh(args: list[str], *, input_data: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gh", *args],
        input=input_data,
        text=True,
        capture_output=True,
        check=check,
    )


def gh_api_json(method: str, endpoint: str, payload: dict[str, Any] | None = None) -> tuple[int, str]:
    cmd = ["api", "-X", method, endpoint, "-H", "Accept: application/vnd.github+json"]
    stdin_text: str | None = None
    if payload is not None:
        cmd.extend(["--input", "-"])
        stdin_text = json.dumps(payload, ensure_ascii=False)
    proc = run_gh(cmd, input_data=stdin_text, check=False)
    return proc.returncode, proc.stdout if proc.returncode == 0 else proc.stderr


def push_payload_to_github(repo: str, branch: str, payload_bytes: bytes, commit_message: str) -> dict[str, Any]:
    encoded_b64 = base64.b64encode(payload_bytes).decode("ascii")
    ref_code, _ = gh_api_json("GET", f"repos/{repo}/git/ref/heads/{branch}")

    if ref_code != 0:
        # Bootstrap an orphan announcements branch with only current.json.
        code, blob_out = gh_api_json(
            "POST",
            f"repos/{repo}/git/blobs",
            {"content": encoded_b64, "encoding": "base64"},
        )
        if code != 0:
            fail(f"failed to create blob on {repo}: {blob_out.strip()}")
        blob_sha = json.loads(blob_out)["sha"]

        code, tree_out = gh_api_json(
            "POST",
            f"repos/{repo}/git/trees",
            {"tree": [{"path": FEED_PATH, "mode": "100644", "type": "blob", "sha": blob_sha}]},
        )
        if code != 0:
            fail(f"failed to create tree on {repo}: {tree_out.strip()}")
        tree_sha = json.loads(tree_out)["sha"]

        code, commit_out = gh_api_json(
            "POST",
            f"repos/{repo}/git/commits",
            {"message": commit_message, "tree": tree_sha, "parents": []},
        )
        if code != 0:
            fail(f"failed to create initial commit on {repo}: {commit_out.strip()}")
        commit_sha = json.loads(commit_out)["sha"]

        code, ref_out = gh_api_json(
            "POST",
            f"repos/{repo}/git/refs",
            {"ref": f"refs/heads/{branch}", "sha": commit_sha},
        )
        if code != 0:
            fail(f"failed to create branch {branch} on {repo}: {ref_out.strip()}")
        return {"branchCreated": True, "commit": commit_sha}

    existing_sha: str | None = None
    get_code, get_out = gh_api_json("GET", f"repos/{repo}/contents/{FEED_PATH}?ref={branch}")
    if get_code == 0:
        existing_sha = json.loads(get_out).get("sha")

    put_body: dict[str, Any] = {
        "message": commit_message,
        "content": encoded_b64,
        "branch": branch,
    }
    if existing_sha:
        put_body["sha"] = existing_sha

    put_code, put_out = gh_api_json("PUT", f"repos/{repo}/contents/{FEED_PATH}", put_body)
    if put_code != 0:
        fail(f"failed to update {FEED_PATH} on {repo} ({branch}): {put_out.strip()}")
    commit_sha = json.loads(put_out).get("commit", {}).get("sha")
    return {"branchCreated": False, "commit": commit_sha}


def handle_publish(args: argparse.Namespace) -> int:
    envelope = build_publish_envelope(args)
    payload_bytes = serialize_envelope(envelope)
    if args.output:
        Path(args.output).write_bytes(payload_bytes)
    if args.dry_run:
        sys.stdout.write(payload_bytes.decode("utf-8"))
        return 0

    announcement = envelope["announcement"]
    result = push_payload_to_github(
        args.repo,
        args.branch,
        payload_bytes,
        f"Publish announcement: {announcement['id']}",
    )
    print(
        json.dumps(
            {
                "status": "published",
                "repo": args.repo,
                "branch": args.branch,
                "id": announcement["id"],
                "rawURL": f"https://raw.githubusercontent.com/{args.repo}/{args.branch}/{FEED_PATH}",
                **result,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def handle_clear(args: argparse.Namespace) -> int:
    envelope = {"schemaVersion": 1, "announcement": None}
    payload_bytes = serialize_envelope(envelope)
    if args.output:
        Path(args.output).write_bytes(payload_bytes)
    if args.dry_run:
        sys.stdout.write(payload_bytes.decode("utf-8"))
        return 0

    result = push_payload_to_github(
        args.repo,
        args.branch,
        payload_bytes,
        "Clear active announcement",
    )
    print(
        json.dumps(
            {
                "status": "cleared",
                "repo": args.repo,
                "branch": args.branch,
                **result,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def handle_status(args: argparse.Namespace) -> int:
    proc = run_gh(
        [
            "api",
            f"repos/{args.repo}/contents/{FEED_PATH}?ref={args.branch}",
            "-H",
            "Accept: application/vnd.github.raw+json",
        ],
        check=False,
    )
    if proc.returncode != 0:
        if "404" in proc.stderr or "Not Found" in proc.stderr:
            print(f"No announcement feed found at {args.repo}:{args.branch}/{FEED_PATH}.")
            return 0
        fail(proc.stderr.strip() or "failed to fetch announcement status.")
    sys.stdout.write(proc.stdout)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage Nexora Glass broadcast announcements.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    pub = subparsers.add_parser("publish", help="Publish or replace the active broadcast announcement.")
    pub.add_argument("--title", required=True, help="Primary announcement title.")
    pub.add_argument("--body", help="Primary announcement body text.")
    pub.add_argument("--body-file", help="Path to UTF-8 text file for the primary announcement body.")
    pub.add_argument("--kind", choices=VALID_KINDS, default="notice", help="Visual category.")
    pub.add_argument("--badge", help="Optional custom badge label.")
    pub.add_argument("--title-en", help="Optional English localized title.")
    pub.add_argument("--body-en", help="Optional English localized body.")
    pub.add_argument("--badge-en", help="Optional English localized badge.")
    pub.add_argument("--action-title", help="Optional CTA button title.")
    pub.add_argument("--action-title-en", help="Optional English CTA button title.")
    pub.add_argument("--action-url", help="Optional https:// CTA URL (no credentials).")
    pub.add_argument("--starts-at", help="Optional ISO-8601 start timestamp.")
    pub.add_argument("--expires-at", help="Optional ISO-8601 expiration timestamp.")
    pub.add_argument("--min-version", help="Optional minimum app version (e.g. 1.0.0).")
    pub.add_argument("--max-version", help="Optional maximum app version (e.g. 1.0.2).")
    pub.add_argument("--display-policy", choices=VALID_DISPLAY_POLICIES, default="once")
    pub.add_argument("--id", help="Optional unique announcement ID.")
    pub.add_argument("--repo", default=DEFAULT_REPO)
    pub.add_argument("--branch", choices=[DEFAULT_BRANCH], default=DEFAULT_BRANCH)
    pub.add_argument("--dry-run", action="store_true", help="Print JSON without pushing to GitHub.")
    pub.add_argument("--output", help="Optional path to write serialized JSON.")
    pub.set_defaults(func=handle_publish)

    clr = subparsers.add_parser("clear", help="Withdraw the active broadcast announcement.")
    clr.add_argument("--repo", default=DEFAULT_REPO)
    clr.add_argument("--branch", choices=[DEFAULT_BRANCH], default=DEFAULT_BRANCH)
    clr.add_argument("--dry-run", action="store_true", help="Print JSON without pushing to GitHub.")
    clr.add_argument("--output", help="Optional path to write serialized JSON.")
    clr.set_defaults(func=handle_clear)

    st = subparsers.add_parser("status", help="Show the currently published announcement JSON.")
    st.add_argument("--repo", default=DEFAULT_REPO)
    st.add_argument("--branch", default=DEFAULT_BRANCH)
    st.set_defaults(func=handle_status)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
