"""VAPID keys, JSON persistence, and Web Push send/schedule."""

from __future__ import annotations

import asyncio
import base64
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
from pywebpush import WebPushException, webpush

from access import AccessDB


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_vapid_keys() -> tuple[str, str]:
    """URL-safe keys compatible with Node `web-push` / browser PushManager."""
    key = ec.generate_private_key(ec.SECP256R1())
    private_raw = key.private_numbers().private_value.to_bytes(32, "big")
    public_raw = key.public_key().public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint,
    )
    return _b64url(public_raw), _b64url(private_raw)


def read_json(path: Path, fallback: Any) -> Any:
    try:
        if not path.exists():
            return fallback
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return fallback


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def parse_at_ms(value: str) -> float | None:
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp() * 1000
    except Exception:
        return None


class Store:
    # Phase pushes more than this late are dropped (not sent). Stops mass
    # "раскрыть"/"посеять" for trays already advanced when schedule was stale.
    _PHASE_LATE_DROP_MS = 5 * 60 * 1000

    def __init__(self) -> None:
        self.data_dir = Path(os.environ.get("DATA_DIR") or Path(__file__).resolve().parent / "data")
        self.static_dir = Path(
            os.environ.get("STATIC_DIR")
            or Path(__file__).resolve().parent.parent.parent / "site"
        )
        self.api_key = os.environ.get("PUSH_API_KEY") or ""
        self.tick_ms = int(os.environ.get("TICK_MS") or 30_000)
        self.default_app_url = os.environ.get("DEFAULT_APP_URL") or "/apps/microgreens/"
        self.vapid_subject = os.environ.get("VAPID_SUBJECT") or "mailto:support@agronizer.ru"

        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.access = AccessDB(data_dir=self.data_dir)
        self.vapid_path = self.data_dir / "vapid.json"
        self.subs_path = self.data_dir / "subscriptions.json"
        self.schedule_path = self.data_dir / "schedules.json"

        self.lock = asyncio.Lock()
        self.vapid = self._load_vapid()
        self.subscriptions: dict[str, dict[str, Any]] = read_json(self.subs_path, {})
        self.schedules: dict[str, list[dict[str, Any]]] = read_json(self.schedule_path, {})
        if not isinstance(self.subscriptions, dict):
            self.subscriptions = {}
        if not isinstance(self.schedules, dict):
            self.schedules = {}
        self.delivered_path = self.data_dir / "delivered.json"
        self.delivered: dict[str, list[str]] = read_json(self.delivered_path, {})
        if not isinstance(self.delivered, dict):
            self.delivered = {}

    def _load_vapid(self) -> dict[str, str]:
        if not self.vapid_path.exists():
            public_key, private_key = generate_vapid_keys()
            vapid = {
                "publicKey": public_key,
                "privateKey": private_key,
                "subject": self.vapid_subject,
            }
            write_json(self.vapid_path, vapid)
            print("Generated new VAPID keys at", self.vapid_path, flush=True)
            return vapid
        vapid = read_json(self.vapid_path, None)
        if not vapid or not vapid.get("publicKey") or not vapid.get("privateKey"):
            raise SystemExit(f"Invalid VAPID keys in {self.vapid_path}")
        vapid.setdefault("subject", self.vapid_subject)
        return vapid

    def save_subs(self) -> None:
        write_json(self.subs_path, self.subscriptions)

    def save_schedules(self) -> None:
        write_json(self.schedule_path, self.schedules)

    def save_delivered(self) -> None:
        write_json(self.delivered_path, self.delivered)

    @staticmethod
    def _delivery_key(item: dict[str, Any]) -> str:
        item_id = str(item.get("id") or "")
        at = str(item.get("at") or "")
        # Tray phase pushes: once per tray id even if the app re-syncs overdue items.
        if item_id.startswith("soak-") or item_id.startswith("germinate-"):
            return item_id
        return f"{item_id}|{at}"

    def _send_sync(self, sub: dict[str, Any], title: str, body: str, data: dict[str, Any]) -> None:
        webpush(
            subscription_info=sub,
            data=json.dumps({"title": title, "body": body, "data": data}),
            vapid_private_key=self.vapid["privateKey"],
            vapid_claims={"sub": self.vapid.get("subject") or self.vapid_subject},
        )

    async def send_to_device(
        self,
        device_id: str,
        title: str,
        body: str,
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        data = data or {}
        async with self.lock:
            sub = self.subscriptions.get(device_id)
        if not sub:
            return {"ok": False, "reason": "no_subscription"}
        try:
            await asyncio.to_thread(self._send_sync, sub, title, body, data)
            return {"ok": True}
        except WebPushException as err:
            status = getattr(err.response, "status_code", None) if err.response is not None else None
            if status in (404, 410):
                async with self.lock:
                    self.subscriptions.pop(device_id, None)
                    self.schedules.pop(device_id, None)
                    self.save_subs()
                    self.save_schedules()
                return {"ok": False, "reason": "gone"}
            print("send failed", device_id, err, flush=True)
            return {"ok": False, "reason": str(err)}
        except Exception as err:
            print("send failed", device_id, err, flush=True)
            return {"ok": False, "reason": str(err)}

    async def tick(self) -> None:
        now = datetime.now(timezone.utc).timestamp() * 1000
        due: list[tuple[str, dict[str, Any]]] = []
        delivered_changed = False
        schedules_changed = False
        async with self.lock:
            for device_id, items in list(self.schedules.items()):
                if not isinstance(items, list):
                    continue
                keep: list[dict[str, Any]] = []
                sent = self.delivered.get(device_id)
                if not isinstance(sent, list):
                    sent = []
                    self.delivered[device_id] = sent
                for item in items:
                    at = parse_at_ms(str(item.get("at") or ""))
                    key = self._delivery_key(item)
                    if key in sent:
                        continue
                    if at is None or at > now:
                        keep.append(item)
                        continue
                    item_id = str(item.get("id") or "")
                    if (
                        (item_id.startswith("soak-") or item_id.startswith("germinate-"))
                        and (now - at) > self._PHASE_LATE_DROP_MS
                    ):
                        # Drop without send; mark delivered so a re-upload of the
                        # same past item cannot fire later.
                        sent.append(key)
                        delivered_changed = True
                        schedules_changed = True
                        if len(sent) > 300:
                            self.delivered[device_id] = sent[-200:]
                        continue
                    due.append((device_id, item))
                    sent.append(key)
                    delivered_changed = True
                    schedules_changed = True
                    if len(sent) > 300:
                        self.delivered[device_id] = sent[-200:]
                self.schedules[device_id] = keep
            if due or schedules_changed:
                self.save_schedules()
            if delivered_changed:
                self.save_delivered()

        for device_id, item in due:
            title = item.get("title") or "Агронайзер"
            body = item.get("body") or ""
            url = item.get("url") or self.default_app_url
            result = await self.send_to_device(device_id, title, body, {"url": url})
            print("due", device_id, item.get("id"), result, flush=True)
