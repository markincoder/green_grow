"""Agronizer portal + PWA/APK static files + shared Web Push API."""

from __future__ import annotations

import asyncio
import html
import os
import re
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import unquote

from dotenv import load_dotenv
from fastapi import APIRouter, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse, RedirectResponse
import httpx

from store import Store
from access import paid_period_label
from auth import auth_router, pick_email, published_app_info, read_session, request_origin, session_email

load_dotenv(Path(__file__).resolve().parent / ".env", override=False)

APP_SLUG = re.compile(r"^[a-z0-9-]+$")
SW_NAME = "flutter_service_worker.js"


def _redirect(url: str, request: Request) -> RedirectResponse:
    query = request.url.query
    if query:
        url = f"{url}&{query}" if "?" in url else f"{url}?{query}"
    return RedirectResponse(url, status_code=301)


def resolve_under_static(root: Path, *parts: str) -> Path | None:
    resolved = (root.joinpath(*parts)).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


async def tick_loop(store: Store) -> None:
    while True:
        try:
            await store.tick()
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            print("tick", exc, flush=True)
        await asyncio.sleep(max(store.tick_ms, 1000) / 1000)


@asynccontextmanager
async def lifespan(app: FastAPI):
    store = Store()
    app.state.store = store
    if not store.static_dir.exists():
        print("STATIC_DIR missing:", store.static_dir, flush=True)
    print(f"agronizer (static + push) on :{os.environ.get('PORT') or 3000}", flush=True)
    print(f"STATIC_DIR={store.static_dir}", flush=True)
    print(f"OAuth Yandex callback: /api/auth/oauth/yandex/callback", flush=True)
    print(f"OAuth VK callback:     /api/auth/oauth/vk/callback", flush=True)
    task = asyncio.create_task(tick_loop(store))
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Agronizer", lifespan=lifespan, docs_url=None, redoc_url=None)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

push_router = APIRouter()


def get_store(request: Request) -> Store:
    return request.app.state.store


def _track_download(request: Request, slug: str | None, kind: str) -> None:
    if not slug or request.method != "GET":
        return
    session = read_session(request)
    if not session:
        return
    try:
        get_store(request).access.record_download(
            user_id=str(session.get("id") or ""),
            slug=slug,
            kind=kind,
        )
    except Exception as exc:
        print("download track", exc, flush=True)


def _terms_accepted(request: Request) -> bool:
    session = read_session(request)
    if not session:
        return False
    return get_store(request).access.has_terms(
        user_id=str(session.get("id") or ""),
    )


@push_router.get("/health")
async def push_health(request: Request):
    store = get_store(request)
    async with store.lock:
        sub_count = len(store.subscriptions)
        sched_count = sum(len(v) for v in store.schedules.values() if isinstance(v, list))
    return {
        "ok": True,
        "service": "agronizer",
        "push": True,
        "subscriptions": sub_count,
        "schedules": sched_count,
    }


@push_router.get("/api/vapid-public-key")
async def vapid_public_key(request: Request):
    return {"publicKey": get_store(request).vapid["publicKey"]}


async def read_json_body(request: Request):
    try:
        payload = await request.json()
    except Exception:
        return None
    return payload if isinstance(payload, dict) else None


@push_router.post("/api/subscribe")
async def subscribe(request: Request):
    payload = await read_json_body(request)
    if payload is None:
        return JSONResponse({"error": "invalid json"}, status_code=400)
    device_id = payload.get("deviceId")
    subscription = payload.get("subscription")
    if not device_id or not isinstance(device_id, str):
        return JSONResponse({"error": "deviceId required"}, status_code=400)
    if not isinstance(subscription, dict) or not subscription.get("endpoint") or not subscription.get("keys"):
        return JSONResponse({"error": "subscription required"}, status_code=400)
    store = get_store(request)
    async with store.lock:
        store.subscriptions[device_id] = subscription
        store.save_subs()
    return {"ok": True}


@push_router.delete("/api/subscribe")
async def unsubscribe(request: Request, deviceId: str | None = None):
    device_id = deviceId
    payload = await read_json_body(request)
    if payload and payload.get("deviceId"):
        device_id = payload["deviceId"]
    if not device_id:
        return JSONResponse({"error": "deviceId required"}, status_code=400)
    store = get_store(request)
    async with store.lock:
        store.subscriptions.pop(device_id, None)
        store.schedules.pop(device_id, None)
        store.save_subs()
        store.save_schedules()
    return {"ok": True}


@push_router.put("/api/schedule")
async def put_schedule(request: Request):
    payload = await read_json_body(request)
    if payload is None:
        return JSONResponse({"error": "invalid json"}, status_code=400)
    device_id = payload.get("deviceId")
    items = payload.get("items")
    if not device_id or not isinstance(device_id, str):
        return JSONResponse({"error": "deviceId required"}, status_code=400)
    store = get_store(request)
    async with store.lock:
        if device_id not in store.subscriptions:
            return JSONResponse({"error": "subscribe first"}, status_code=404)
        if not isinstance(items, list):
            return JSONResponse({"error": "items array required"}, status_code=400)
        cleaned = []
        for item in items:
            if not item or not item.get("id") or not item.get("at") or not item.get("body"):
                continue
            cleaned.append(
                {
                    "id": str(item["id"]),
                    "at": str(item["at"]),
                    "title": str(item.get("title") or "Агронайзер"),
                    "body": str(item["body"]),
                    "url": str(item["url"]) if item.get("url") else store.default_app_url,
                }
            )
        store.schedules[device_id] = cleaned
        store.save_schedules()
        count = len(cleaned)
    return {"ok": True, "count": count}


@push_router.post("/api/send")
async def send(request: Request):
    store = get_store(request)
    if store.api_key:
        key = request.headers.get("x-api-key") or ""
        if key != store.api_key:
            return JSONResponse({"error": "unauthorized"}, status_code=401)
    payload = await read_json_body(request)
    if payload is None:
        return JSONResponse({"error": "invalid json"}, status_code=400)
    title = payload.get("title")
    body = payload.get("body")
    if not title or not body:
        return JSONResponse({"error": "title and body required"}, status_code=400)
    url = payload.get("url") or store.default_app_url
    data = {"url": url}
    device_id = payload.get("deviceId")
    if device_id:
        return await store.send_to_device(str(device_id), str(title), str(body), data)
    async with store.lock:
        ids = list(store.subscriptions.keys())
    results = {}
    for item_id in ids:
        results[item_id] = await store.send_to_device(item_id, str(title), str(body), data)
    return {"ok": True, "results": results}


app.include_router(push_router, prefix="/push")
app.include_router(auth_router)


@app.get("/health")
async def health(request: Request):
    store = get_store(request)
    return {
        "ok": True,
        "service": "agronizer",
        "staticDir": str(store.static_dir),
        "staticOk": store.static_dir.exists(),
        "oauth": {
            "yandexStart": "/api/auth/oauth/yandex/start",
            "yandexCallback": "/api/auth/oauth/yandex/callback",
            "vkStart": "/api/auth/oauth/vk/start",
            "vkCallback": "/api/auth/oauth/vk/callback",
        },
    }


@app.get("/app")
@app.get("/app/")
async def legacy_app_root(request: Request):
    return _redirect("/apps/microgreens/", request)


@app.get("/app/{rest:path}")
async def legacy_app_path(rest: str, request: Request):
    return _redirect(f"/apps/microgreens/{rest}", request)


@app.get("/green_grow.apk")
async def legacy_apk(request: Request):
    return _redirect("/apps/microgreens/microgreens.apk", request)


def _env_clean(name: str) -> str:
    return (os.environ.get(name) or "").strip().strip('"').strip("'")


def _pay_env() -> dict[str, str]:
    shop_id = _env_clean("YOOKASSA_SHOP_ID")
    sum_raw = os.environ.get("YOOKASSA_SUM", "300").strip() or "300"
    return_url = (
        os.environ.get("YOOKASSA_RETURN_URL") or os.environ.get("SITE_URL") or "https://agronizer.ru/"
    ).strip()
    if return_url and not return_url.endswith("/"):
        return_url += "/"
    try:
        amount = float(sum_raw.replace(",", "."))
    except ValueError:
        amount = 300.0
    sum_value = str(int(amount)) if amount == int(amount) else f"{amount:.2f}"
    sum_label = f"{amount:,.2f}".replace(",", " ").replace(".", ",")
    return {
        "YOOKASSA_SHOP_ID": shop_id,
        "YOOKASSA_SUM": sum_value,
        "YOOKASSA_SUM_LABEL": sum_label,
        "YOOKASSA_RETURN_URL": return_url,
    }


def _fill_html_env(text: str, extra: dict[str, str] | None = None) -> str | None:
    if "{{YOOKASSA_" not in text and "{{USER_" not in text and "{{PAID_" not in text:
        return None
    values = {**_pay_env(), **(extra or {})}
    values.setdefault("USER_EMAIL", "")
    values.setdefault("PAID_PERIOD_LABEL", paid_period_label())
    if "{{YOOKASSA_SHOP_ID}}" in text and not re.fullmatch(r"\d+", values["YOOKASSA_SHOP_ID"]):
        return ""
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", html.escape(value, quote=True))
    return text


def _html_or_file(path: Path, slug: str | None = None, extra: dict[str, str] | None = None):
    if path.suffix.lower() == ".html":
        rendered = _fill_html_env(path.read_text(encoding="utf-8"), extra)
        if rendered == "":
            return PlainTextResponse(
                "YooKassa is not configured. Set YOOKASSA_SHOP_ID in platform/push/.env",
                status_code=503,
            )
        if rendered is not None:
            return HTMLResponse(rendered, headers={"Cache-Control": "no-store"})
    return _send_file(path, slug)


@app.get("/pay/{slug}")
@app.get("/pay/{slug}/")
async def pay_page(slug: str, request: Request):
    if not APP_SLUG.match(slug):
        return PlainTextResponse("Not found", status_code=404)
    if not request.url.path.endswith("/"):
        return _redirect(f"/pay/{slug}/", request)
    store = get_store(request)
    index = resolve_under_static(store.static_dir, "pay", slug, "index.html")
    if not index or not index.is_file():
        return PlainTextResponse("Not found", status_code=404)
    return _html_or_file(index, extra={"USER_EMAIL": session_email(request)})


def _yookassa_auth() -> tuple[str, str]:
    return _env_clean("YOOKASSA_SHOP_ID"), _env_clean("YOOKASSA_SECRET_KEY")


def _access_payload(row: dict) -> dict:
    return {
        "ok": True,
        "already": True,
        "accessCode": row.get("code") or "",
        "purchasedAt": row.get("purchased_at") or "",
        "expiresAt": row.get("expires_at") or "",
        "activatedAt": row.get("activated_at") or "",
    }


def _pay_return_url(request: Request, slug: str) -> str:
    env_url = (_env_clean("YOOKASSA_RETURN_URL") or "").strip()
    if env_url:
        return env_url if env_url.endswith("/") else env_url + "/"
    return f"{request_origin(request)}/pay/{slug}/"


async def _yookassa_create_payment(payload: dict) -> httpx.Response:
    shop_id, secret = _yookassa_auth()
    print(
        f"yookassa shop={shop_id} key_prefix={secret[:5]} key_len={len(secret)}",
        flush=True,
    )
    async with httpx.AsyncClient(timeout=20) as client:
        return await client.post(
            "https://api.yookassa.ru/v3/payments",
            json=payload,
            auth=(shop_id, secret),
            headers={"Idempotence-Key": str(uuid.uuid4())},
        )


async def _yookassa_get_payment(payment_id: str) -> dict | None:
    shop_id, secret = _yookassa_auth()
    if not shop_id or not secret or not payment_id:
        return None
    async with httpx.AsyncClient(timeout=20) as client:
        res = await client.get(
            f"https://api.yookassa.ru/v3/payments/{payment_id}",
            auth=(shop_id, secret),
        )
    if res.status_code >= 400:
        print(f"yookassa get {payment_id} {res.status_code} {res.text[:180]}", flush=True)
        return None
    data = res.json()
    return data if isinstance(data, dict) else None


def _grant_from_payment(store: Store, payment: dict, fallback: dict | None = None) -> dict | None:
    if (payment.get("status") or "") != "succeeded":
        if payment.get("status") in ("canceled", "cancelled"):
            store.access.mark_payment(str(payment.get("id") or ""), "canceled")
        return None
    meta = payment.get("metadata") if isinstance(payment.get("metadata"), dict) else {}
    pending = store.access.get_payment(str(payment.get("id") or "")) or {}
    extra = fallback or {}
    email = pick_email(
        pending.get("email"),
        meta.get("email"),
        extra.get("email"),
    )
    user_id = str(pending.get("user_id") or meta.get("user_id") or extra.get("user_id") or "")
    slug = str(pending.get("slug") or meta.get("slug") or extra.get("slug") or "microgreens")
    payment_id = str(payment.get("id") or "")
    if not email and not user_id:
        print(f"yookassa succeeded {payment_id} but no email/user", flush=True)
        return None
    row = store.access.grant(email=email, user_id=user_id, slug=slug, payment_id=payment_id)
    print(f"access granted slug={slug} payment={payment_id}", flush=True)
    return row


@app.post("/api/pay/complete")
async def complete_payment(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False, "error": "auth"}, status_code=401)
    store = get_store(request)
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = session_email(request)
    user_id = str(session.get("id") or "")
    existing = store.access.find(user_id=user_id, email=email, slug="microgreens")
    payment_id = str((body or {}).get("paymentId") or "")
    ids = [payment_id] if payment_id else [row["payment_id"] for row in store.access.pending_for_user(user_id)]
    granted = existing
    for pid in ids:
        payment = await _yookassa_get_payment(str(pid))
        if not payment:
            continue
        row = _grant_from_payment(
            store,
            payment,
            {"user_id": user_id, "email": email, "slug": "microgreens"},
        )
        if row:
            granted = row
    if granted:
        return _access_payload(granted)
    if ids:
        return {"ok": True, "pending": True}
    return {"ok": True}


@app.post("/api/pay/notify")
async def yookassa_notify(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"ok": False}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"ok": False}, status_code=400)
    obj = body.get("object") if isinstance(body.get("object"), dict) else {}
    payment_id = str(obj.get("id") or "")
    if not payment_id:
        return {"ok": True}
    payment = await _yookassa_get_payment(payment_id)
    if not payment:
        return JSONResponse({"ok": False}, status_code=502)
    _grant_from_payment(get_store(request), payment)
    return {"ok": True}


@app.post("/api/pay/{slug}")
async def create_payment(slug: str, request: Request):
    if slug in ("complete", "notify") or not APP_SLUG.match(slug):
        return JSONResponse({"ok": False, "error": "not_found"}, status_code=404)
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False, "error": "auth"}, status_code=401)
    if not _terms_accepted(request):
        return JSONResponse({"ok": False, "error": "terms"}, status_code=403)
    store = get_store(request)
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = pick_email(body.get("email") if isinstance(body, dict) else "") or session_email(request)
    existing = store.access.find(user_id=str(session.get("id") or ""), email=email, slug=slug)
    if existing:
        return _access_payload(existing)
    env = _pay_env()
    if not re.fullmatch(r"\d+", env["YOOKASSA_SHOP_ID"]) or not _env_clean("YOOKASSA_SECRET_KEY"):
        return JSONResponse({"ok": False, "error": "pay_config"}, status_code=503)
    try:
        amount = f"{float(env['YOOKASSA_SUM'].replace(',', '.')):.2f}"
    except ValueError:
        amount = "300.00"
    label = paid_period_label()
    names = {"microgreens": f"Доступ Микрозелень на {label}"}
    description = names.get(slug, f"Доступ Агронайзер на {label}")
    return_url = _pay_return_url(request, slug)
    payload: dict = {
        "amount": {"value": amount, "currency": "RUB"},
        "capture": True,
        "confirmation": {"type": "redirect", "return_url": return_url},
        "description": description,
        "metadata": {
            "user_id": session.get("id") or "",
            "slug": slug,
            "email": email,
        },
    }
    if email:
        payload["receipt"] = {
            "customer": {"email": email},
            "items": [
                {
                    "description": description,
                    "quantity": "1.00",
                    "amount": {"value": amount, "currency": "RUB"},
                    "vat_code": 1,
                    "payment_mode": "full_prepayment",
                    "payment_subject": "service",
                }
            ],
        }
    res = await _yookassa_create_payment(payload)
    if res.status_code == 401:
        print("yookassa invalid_credentials", flush=True)
        return JSONResponse({"ok": False, "error": "invalid_credentials"}, status_code=502)
    if res.status_code >= 400 and "receipt" in payload:
        print(f"yookassa receipt failed {res.status_code} {res.text[:240]}", flush=True)
        payload.pop("receipt", None)
        res = await _yookassa_create_payment(payload)
        if res.status_code == 401:
            return JSONResponse({"ok": False, "error": "invalid_credentials"}, status_code=502)
    if res.status_code >= 400:
        print(f"yookassa create failed {res.status_code} {res.text[:240]}", flush=True)
        return JSONResponse({"ok": False, "error": "yookassa"}, status_code=502)
    data = res.json()
    url = (data.get("confirmation") or {}).get("confirmation_url")
    payment_id = str(data.get("id") or "")
    if not url or not payment_id:
        return JSONResponse({"ok": False, "error": "yookassa"}, status_code=502)
    store.access.save_payment(payment_id, str(session.get("id") or ""), slug)
    return {"ok": True, "confirmationUrl": url}


@app.post("/api/download")
async def api_download(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False, "error": "auth"}, status_code=401)
    if not _terms_accepted(request):
        return JSONResponse({"ok": False, "error": "terms"}, status_code=403)
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    kind = str(body.get("kind") or "").strip().lower()
    if kind not in ("apk", "pwa"):
        return JSONResponse({"ok": False, "error": "kind"}, status_code=400)
    slug = str(body.get("slug") or "microgreens")
    if not APP_SLUG.match(slug):
        slug = "microgreens"
    count = get_store(request).access.record_download(
        user_id=str(session.get("id") or ""),
        slug=slug,
        kind=kind,
    )
    return {"ok": True, "downloadCount": count}


@app.post("/api/access/activate")
async def activate_access(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    if not isinstance(body, dict):
        body = {}
    code = str(body.get("code") or "")
    email = pick_email(body.get("email"))
    slug = str(body.get("slug") or "microgreens")
    if not APP_SLUG.match(slug):
        slug = "microgreens"
    error, row = get_store(request).access.activate_code(
        code,
        email,
        slug,
        record=not bool(body.get("checkOnly")),
    )
    if error == "mismatch":
        return JSONResponse({"ok": False, "error": "mismatch"}, status_code=404)
    if error == "limit":
        return JSONResponse({"ok": False, "error": "limit"}, status_code=403)
    if error == "expired":
        payload = {"ok": False, "error": "expired"}
        if row and row.get("expires_at"):
            payload["expiresAt"] = row["expires_at"]
        return JSONResponse(payload, status_code=410)
    if error or not row:
        return JSONResponse({"ok": False, "error": "invalid"}, status_code=404)
    return {
        "ok": True,
        "expiresAt": row.get("expires_at") or "",
        "purchasedAt": row.get("purchased_at") or "",
        "activatedAt": row.get("activated_at") or "",
    }


def _file_headers(path: Path, slug: str | None = None) -> tuple[str | None, dict[str, str]]:
    headers: dict[str, str] = {}
    media_type = None
    suffix = path.suffix.lower()
    name = path.name.lower()

    if suffix in {".html", ".htm"}:
        media_type = "text/html; charset=utf-8"
    if name == "robots.txt" or suffix == ".txt":
        media_type = "text/plain; charset=utf-8"
        headers.setdefault("Cache-Control", "no-cache")
    if name == "sitemap.xml" or suffix == ".xml":
        media_type = "application/xml; charset=utf-8"
        headers.setdefault("Cache-Control", "no-cache")
    if suffix == ".apk":
        media_type = "application/vnd.android.package-archive"
        headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        info = published_app_info("")
        version = str(info.get("appVersion") or "").strip()
        filename = f"microgreens-{version}.apk" if version else "microgreens.apk"
        headers["Content-Disposition"] = f'attachment; filename="{filename}"'
    if suffix in {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}:
        # Logos/icons keep the same URL after rebuild; do not pin them for a week.
        headers.setdefault("Cache-Control", "no-cache")
    elif "assets" in path.parts:
        headers.setdefault("Cache-Control", "public, max-age=604800")
    if name in {
        "index.html",
        "flutter_bootstrap.js",
        "flutter.js",
        "main.dart.js",
        "version.json",
        "pwa_update.js",
    }:
        headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    if name == "manifest.json":
        media_type = "application/manifest+json; charset=utf-8"
        headers.setdefault("Cache-Control", "no-cache")
    if name == SW_NAME and slug:
        media_type = "application/javascript; charset=utf-8"
        headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        headers["Service-Worker-Allowed"] = f"/apps/{slug}/"
    return media_type, headers


def _send_file(path: Path, slug: str | None = None) -> FileResponse:
    media_type, headers = _file_headers(path, slug)
    return FileResponse(path, media_type=media_type, headers=headers)


@app.api_route("/{full_path:path}", methods=["GET", "HEAD"])
async def serve_static(request: Request, full_path: str = ""):
    store = get_store(request)
    root = store.static_dir
    rel = unquote(full_path).replace("\\", "/").lstrip("/")
    parts = [p for p in rel.split("/") if p not in ("", ".")]
    if any(p == ".." for p in parts):
        return PlainTextResponse("Not found", status_code=404)

    if parts and parts[0] in ("api", "push", "health"):
        return PlainTextResponse("Not found", status_code=404)

    slug = parts[1] if len(parts) >= 2 and parts[0] == "apps" and APP_SLUG.match(parts[1]) else None

    if slug and len(parts) == 3 and parts[2].lower() == SW_NAME:
        file_path = resolve_under_static(root, "apps", slug, SW_NAME)
        if file_path and file_path.is_file():
            return _send_file(file_path, slug)

    if slug and len(parts) == 3 and parts[2].lower() == "manifest.json":
        file_path = resolve_under_static(root, "apps", slug, "manifest.json")
        if file_path and file_path.is_file():
            return _send_file(file_path, slug)

    target = resolve_under_static(root, *parts) if parts else root.resolve()
    if target is None:
        return PlainTextResponse("Not found", status_code=404)

    if target.is_file():
        if slug and target.suffix.lower() == ".apk":
            _track_download(request, slug, "apk")
        elif (
            slug
            and target.name.lower() == "index.html"
            and request.query_params.get("setup") == "1"
        ):
            _track_download(request, slug, "pwa")
        return _html_or_file(target, slug)

    if target.is_dir():
        index = target / "index.html"
        if not rel.endswith("/") and rel != "":
            return _redirect(f"/{rel}/", request)
        if index.is_file():
            if slug and request.query_params.get("setup") == "1":
                _track_download(request, slug, "pwa")
            return _html_or_file(index, slug)

    if slug and (len(parts) == 2 or (len(parts) > 2 and "." not in parts[-1])):
        index = resolve_under_static(root, "apps", slug, "index.html")
        if index and index.is_file():
            if len(parts) == 2 and not rel.endswith("/"):
                return _redirect(f"/apps/{slug}/", request)
            if request.query_params.get("setup") == "1":
                _track_download(request, slug, "pwa")
            return _send_file(index, slug)

    return PlainTextResponse("Not found", status_code=404)
