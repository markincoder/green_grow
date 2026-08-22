"""Download a Google Play-signed APK (App Signing key) for sideloading.

Requires a Play Console service account JSON. Generated APKs exist only after
Play has processed an uploaded AAB — this cannot be done with the local keystore.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCOPE = "https://www.googleapis.com/auth/androidpublisher"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"


def _session(json_key: Path):
    try:
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account
    except ImportError:
        sys.exit(
            "Need google-auth: py -m pip install google-auth\n"
            "Then: Play Console → Users → invite the service account as Releases."
        )
    creds = service_account.Credentials.from_service_account_file(
        str(json_key),
        scopes=[SCOPE],
    )
    return AuthorizedSession(creds)


def _get(session, url: str) -> dict:
    res = session.get(url, timeout=60)
    if not res.ok:
        sys.exit(f"Play API {res.status_code} {url}\n{res.text[:800]}")
    return res.json()


def _latest_version(session, package: str, track: str) -> int:
    started = session.post(f"{API}/applications/{package}/edits", json={}, timeout=60)
    if not started.ok:
        sys.exit(f"Cannot create Play edit: {started.status_code}\n{started.text[:800]}")
    edit_id = started.json()["id"]
    try:
        data = _get(session, f"{API}/applications/{package}/edits/{edit_id}/tracks/{track}")
    finally:
        session.delete(f"{API}/applications/{package}/edits/{edit_id}", timeout=60)
    codes: list[int] = []
    for rel in data.get("releases") or []:
        for raw in rel.get("versionCodes") or []:
            codes.append(int(raw))
    if not codes:
        sys.exit(f"No versionCodes on Play track '{track}' for {package}")
    return max(codes)


def _pick_download(generated: dict) -> tuple[str, str, str]:
    groups = generated.get("generatedApks") or []
    if not groups:
        sys.exit("Play has not generated APKs yet. Wait a few minutes after the AAB upload.")
    group = groups[0]
    cert = group.get("certificateSha256Hash") or ""
    universal = (group.get("generatedUniversalApk") or {}).get("downloadId")
    if universal:
        return universal, "universal", cert
    standalones = group.get("generatedStandaloneApks") or []
    if standalones and standalones[0].get("downloadId"):
        return standalones[0]["downloadId"], "standalone", cert
    sys.exit("No universal/standalone APK in generated list (only split APKs).")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="com.agronizer.greengrow")
    parser.add_argument("--version-code", type=int, default=0)
    parser.add_argument("--track", default="internal")
    parser.add_argument("--json-key", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    json_key = Path(args.json_key)
    if not json_key.is_file():
        sys.exit(f"Service account JSON not found: {json_key}")

    session = _session(json_key)
    version = args.version_code or _latest_version(session, args.package, args.track)
    print(f"Play package={args.package} versionCode={version} track={args.track}")

    listed = _get(session, f"{API}/applications/{args.package}/generatedApks/{version}")
    download_id, kind, cert = _pick_download(listed)
    url = (
        f"{API}/applications/{args.package}/generatedApks/{version}"
        f"/downloads/{download_id}:download?alt=media"
    )
    res = session.get(url, timeout=300)
    if not res.ok:
        sys.exit(f"Download failed {res.status_code}\n{res.text[:800]}")
    data = res.content
    if len(data) < 1_000_000 or data[:2] != b"PK":
        sys.exit(f"Not an APK ({len(data)} bytes). Body: {data[:200]!r}")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    mb = len(data) / (1024 * 1024)
    print(f"Downloaded {kind} APK -> {out} ({mb:.1f} MB)")
    if cert:
        print(f"Play signing cert SHA-256: {cert}")


if __name__ == "__main__":
    main()
