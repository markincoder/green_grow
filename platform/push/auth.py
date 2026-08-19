"""Yandex / VK OAuth and signed session cookies."""

from __future__ import annotations

import base64
import hmac
import hashlib
import json
import os
import secrets
import smtplib
from email.message import EmailMessage
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse, Response
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from access import TERMS_VERSION, paid_period_label, paid_period_months

SESSION_COOKIE = "agronizer_session"
OAUTH_COOKIE = "agronizer_oauth"
SESSION_MAX_AGE = 60 * 60 * 24 * 30
OAUTH_MAX_AGE = 600

auth_router = APIRouter()


def _secret() -> str:
    secret = (os.environ.get("SESSION_SECRET") or "").strip()
    if secret:
        return secret
    yandex = os.environ.get("YANDEX_OAUTH_CLIENT_SECRET") or ""
    vk = os.environ.get("VK_OAUTH_CLIENT_SECRET") or os.environ.get("VK_OAUTH_SECRET_KEY") or ""
    return (yandex + vk) or "agronizer-dev-session"


def _signer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(_secret(), salt="agronizer-auth")


def public_base_url() -> str:
    return (
        os.environ.get("SITE_URL")
        or os.environ.get("NEXT_PUBLIC_APP_URL")
        or os.environ.get("YOOKASSA_RETURN_URL")
        or "https://agronizer.ru"
    ).rstrip("/")


def request_origin(request: Request) -> str:
    proto = (request.headers.get("x-forwarded-proto") or request.url.scheme or "http").split(",")[0].strip()
    host = (request.headers.get("x-forwarded-host") or request.headers.get("host") or "").split(",")[0].strip()
    if host:
        return f"{proto}://{host}".rstrip("/")
    return public_base_url()


def oauth_redirect_uri(request: Request, provider: str) -> str:
    env_key = "YANDEX_OAUTH_REDIRECT_URI" if provider == "yandex" else "VK_OAUTH_REDIRECT_URI"
    explicit = (os.environ.get(env_key) or "").strip()
    if explicit:
        return explicit
    return f"{request_origin(request)}/api/auth/oauth/{provider}/callback"


def yandex_configured() -> bool:
    return bool(
        (os.environ.get("YANDEX_OAUTH_CLIENT_ID") or "").strip()
        and (os.environ.get("YANDEX_OAUTH_CLIENT_SECRET") or "").strip()
    )


def vk_configured() -> bool:
    return bool(
        (os.environ.get("VK_OAUTH_CLIENT_ID") or "").strip()
        and (
            (os.environ.get("VK_OAUTH_CLIENT_SECRET") or "").strip()
            or (os.environ.get("VK_OAUTH_SECRET_KEY") or "").strip()
        )
    )


def _cookie_secure(request: Request) -> bool:
    proto = (request.headers.get("x-forwarded-proto") or request.url.scheme or "http").split(",")[0].strip()
    return proto == "https"


def _safe_next(value: str | None) -> str:
    if value and value.startswith("/") and not value.startswith("//"):
        return value
    return "/?download=1"


def read_session(request: Request) -> dict[str, Any] | None:
    raw = request.cookies.get(SESSION_COOKIE)
    if not raw:
        return None
    try:
        data = _signer().loads(raw, max_age=SESSION_MAX_AGE)
    except (BadSignature, SignatureExpired):
        return None
    return data if isinstance(data, dict) and data.get("id") else None


def _looks_like_email(value: str) -> bool:
    text = value.strip()
    if "@" not in text or " " in text:
        return False
    local, _, domain = text.partition("@")
    return bool(local and "." in domain)


def _normalize_email(value: str) -> str:
    text = pick_email(value)
    return text.strip().lower() if text else ""


def pick_email(*candidates: Any) -> str:
    for item in candidates:
        if isinstance(item, list):
            found = pick_email(*item)
            if found:
                return found
        elif isinstance(item, dict):
            found = pick_email(item.get("email"), item.get("default_email"))
            if found:
                return found
        elif isinstance(item, str) and _looks_like_email(item):
            return item.strip()
    return ""


def email_from_jwt(token: Any) -> str:
    if not isinstance(token, str) or token.count(".") < 2:
        return ""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
        if not isinstance(data, dict):
            return ""
        return pick_email(data.get("email"), data.get("emails"), data.get("preferred_username"))
    except Exception:
        return ""


def yandex_email(info: dict[str, Any]) -> str:
    email = pick_email(
        info.get("default_email"),
        info.get("emails"),
        info.get("email"),
        info.get("login"),
    )
    if email:
        return email
    login = str(info.get("login") or "").strip()
    if login and "@" not in login and " " not in login:
        return f"{login}@yandex.ru"
    return ""


def _set_session_cookie(response: Response, request: Request, user: dict[str, Any]) -> None:
    token = _signer().dumps(
        {
            "id": user["id"],
            "provider": user.get("provider"),
            "name": user.get("name") or "",
            "email": user.get("email") or "",
        }
    )
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=SESSION_MAX_AGE,
        httponly=True,
        samesite="lax",
        secure=_cookie_secure(request),
        path="/",
    )


def _users(request: Request):
    return request.app.state.store.access


def _session_user(user: dict[str, Any], provider: str | None = None) -> dict[str, Any]:
    data = dict(user)
    if provider:
        data["provider"] = provider
    data["id"] = str(data.get("id") or data.get("user_id") or "")
    return data


def _pbkdf2_hash(password: str, salt: bytes, rounds: int = 200_000) -> str:
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, rounds)
    return f"pbkdf2_sha256${rounds}${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def _hash_password(password: str) -> str:
    return _pbkdf2_hash(password, secrets.token_bytes(16))


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algo, rounds_raw, salt_raw, digest_raw = str(encoded).split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        rounds = int(rounds_raw)
        salt = base64.urlsafe_b64decode(salt_raw.encode("utf-8"))
        expected = _pbkdf2_hash(password, salt, rounds)
        return hmac.compare_digest(expected, encoded)
    except Exception:
        return False


def _temp_password() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    return "".join(secrets.choice(alphabet) for _ in range(10))


def _email_code() -> str:
    return "".join(secrets.choice("0123456789") for _ in range(6))


def upsert_user(
    request: Request, provider: str, provider_id: str, name: str, email: str = ""
) -> dict[str, Any]:
    user = _users(request).upsert_oauth_user(provider, str(provider_id), name, email)
    return _session_user(user, provider)


def lookup_user_email(request: Request, user_id: str) -> str:
    row = _users(request).find_user(user_id=user_id)
    return pick_email((row or {}).get("email"))


def session_user_row(request: Request) -> dict[str, Any] | None:
    session = read_session(request)
    if not session:
        return None
    return _users(request).find_user(
        user_id=str(session.get("id") or ""),
        email=pick_email(session.get("email")),
    )


def session_email(request: Request) -> str:
    session = read_session(request)
    if not session:
        return ""
    row = session_user_row(request)
    return pick_email((row or {}).get("email"), session.get("email"))


def _smtp_config() -> dict[str, Any] | None:
    host = (os.environ.get("SMTP_HOST") or "").strip()
    if not host:
        return None
    port_raw = (os.environ.get("SMTP_PORT") or "587").strip()
    try:
        port = int(port_raw)
    except ValueError:
        port = 587
    user = (os.environ.get("SMTP_USER") or "").strip()
    password = os.environ.get("SMTP_PASS") or ""
    sender = (os.environ.get("SMTP_FROM") or user or "no-reply@agronizer.ru").strip()
    use_tls = (os.environ.get("SMTP_TLS") or "1").strip() not in {"0", "false", "False"}
    return {
        "host": host,
        "port": port,
        "user": user,
        "password": password,
        "sender": sender,
        "tls": use_tls,
    }


def _send_temp_password(email: str, password: str) -> bool:
    return _send_mail(
        email=email,
        subject="Временный пароль — Агронайзер",
        body=(
            "Вы запросили восстановление пароля в Агронайзер.\n\n"
            f"Временный пароль: {password}\n\n"
            "После входа нажмите «Сменить пароль» в правом верхнем углу сайта.\n"
        ),
        log_prefix="password reset mail",
    )


def _send_verification_code(email: str, code: str) -> bool:
    return _send_mail(
        email=email,
        subject="Код подтверждения email — Агронайзер",
        body=(
            "Вы регистрируетесь в Агронайзер.\n\n"
            f"Код подтверждения: {code}\n\n"
            "Введите его в форме регистрации на сайте. Код действует 15 минут.\n"
        ),
        log_prefix="email verification mail",
    )


def _send_mail(email: str, subject: str, body: str, log_prefix: str) -> bool:
    cfg = _smtp_config()
    if not cfg:
        print(f"{log_prefix}: SMTP is not configured", flush=True)
        return False
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = cfg["sender"]
    msg["To"] = email
    msg.set_content(body)
    try:
        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=20) as smtp:
            if cfg["tls"]:
                smtp.starttls()
            if cfg["user"]:
                smtp.login(cfg["user"], cfg["password"])
            smtp.send_message(msg)
        return True
    except smtplib.SMTPAuthenticationError as exc:
        code = getattr(exc, "smtp_code", "")
        raw = getattr(exc, "smtp_error", b"")
        if isinstance(raw, bytes):
            detail = raw.decode("utf-8", errors="replace")
        else:
            detail = str(raw)
        print(
            f"{log_prefix} auth error: "
            f"host={cfg['host']} port={cfg['port']} tls={cfg['tls']} "
            f"user={cfg['user']!r} from={cfg['sender']!r} "
            f"code={code} detail={detail}",
            flush=True,
        )
        return False
    except smtplib.SMTPException as exc:
        code = getattr(exc, "smtp_code", "")
        raw = getattr(exc, "smtp_error", b"")
        if isinstance(raw, bytes):
            detail = raw.decode("utf-8", errors="replace")
        else:
            detail = str(raw)
        print(
            f"{log_prefix} smtp error: "
            f"{type(exc).__name__} "
            f"host={cfg['host']} port={cfg['port']} tls={cfg['tls']} "
            f"user={cfg['user']!r} from={cfg['sender']!r} "
            f"code={code} detail={detail}",
            flush=True,
        )
        return False
    except Exception as exc:
        print(
            f"{log_prefix} error: "
            f"{type(exc).__name__} "
            f"host={cfg['host']} port={cfg['port']} tls={cfg['tls']} "
            f"user={cfg['user']!r} from={cfg['sender']!r} "
            f"detail={exc}",
            flush=True,
        )
        return False


def trial_period_days() -> int:
    raw = (os.environ.get("TRIAL_PERIOD") or "7").strip()
    try:
        days = int(float(raw.replace(",", ".")))
    except ValueError:
        days = 7
    return max(1, days)


def _static_dir() -> Path:
    raw = (os.environ.get("STATIC_DIR") or "").strip()
    if raw:
        return Path(raw)
    return Path(__file__).resolve().parent.parent.parent / "site"


def published_app_info(site: str) -> dict[str, Any]:
    """Latest shipped app version from Flutter `version.json` after PWA/APK build."""
    version = ""
    build = 0
    path = _static_dir() / "apps" / "microgreens" / "version.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            version = str(data.get("version") or "").strip()
            raw_build = data.get("build_number")
            if raw_build not in (None, ""):
                build = int(str(raw_build).strip())
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    base = site.rstrip("/")
    return {
        "appVersion": version,
        "appBuild": build,
        "apkUrl": f"{base}/apps/microgreens/microgreens.apk",
        "pwaUrl": f"{base}/apps/microgreens/",
    }


@auth_router.get("/api/config")
async def api_config(request: Request):
    sum_raw = (os.environ.get("YOOKASSA_SUM") or "300").strip() or "300"
    try:
        amount = float(sum_raw.replace(",", "."))
    except ValueError:
        amount = 300.0
    yookassa_sum = str(int(amount)) if amount == int(amount) else f"{amount:.2f}".replace(".", ",")
    site = public_base_url()
    return {
        "oauthYandex": yandex_configured(),
        "oauthVk": vk_configured(),
        "passwordAuth": True,
        "yandexRedirectUri": oauth_redirect_uri(request, "yandex"),
        "vkRedirectUri": oauth_redirect_uri(request, "vk"),
        "yookassaSum": yookassa_sum,
        "trialPeriod": trial_period_days(),
        "paidPeriod": paid_period_months(),
        "paidPeriodLabel": paid_period_label(),
        "siteUrl": site,
        **published_app_info(site),
    }


@auth_router.get("/api/auth/me")
async def auth_me(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"guest": True})
    row = session_user_row(request)
    email = pick_email((row or {}).get("email"), session.get("email"))
    uid = str((row or {}).get("id") or session.get("id") or "")
    payload = {
        "guest": False,
        "id": uid,
        "provider": session.get("provider") or (row or {}).get("provider") or "",
        "name": (row or {}).get("name") or session.get("name") or "",
        "email": email,
        "hasPassword": bool(row and row.get("hasPassword")),
        "mustChangePassword": bool(row and row.get("mustChangePassword")),
    }
    access = request.app.state.store.access.find(
        user_id=uid,
        email=email,
        slug="microgreens",
    )
    download = request.app.state.store.access.get_download(
        user_id=uid,
        slug="microgreens",
    )
    if access:
        payload["accessCode"] = access["code"]
        payload["purchasedAt"] = access["purchased_at"]
        payload["expiresAt"] = access.get("expires_at") or ""
        payload["activatedAt"] = access.get("activated_at") or ""
    if download:
        payload["downloadKind"] = download.get("kind") or ""
        payload["downloadedAt"] = download.get("downloaded_at") or ""
        payload["downloadCount"] = int(download.get("download_count") or 0)
    payload["termsAccepted"] = request.app.state.store.access.has_terms(user_id=uid)
    payload["termsVersion"] = TERMS_VERSION
    response = JSONResponse(payload)
    if row and str(session.get("id") or "") != uid:
        _set_session_cookie(response, request, _session_user(row, str(payload["provider"])))
    return response


@auth_router.post("/api/auth/password/register")
async def auth_password_register(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = _normalize_email(body.get("email") if isinstance(body, dict) else "")
    password = str(body.get("password") if isinstance(body, dict) else "")
    if not email:
        return JSONResponse({"ok": False, "error": "email_required"}, status_code=400)
    if len(password) < 8:
        return JSONResponse({"ok": False, "error": "password_short"}, status_code=400)
    if not _users(request).consume_verified_email(email):
        return JSONResponse({"ok": False, "error": "email_not_verified"}, status_code=400)
    error, user = _users(request).register_password_user(email, _hash_password(password))
    if error == "exists" or not user:
        return JSONResponse({"ok": False, "error": error or "exists"}, status_code=409 if error == "exists" else 400)
    session = _session_user(user, "password")
    response = JSONResponse({"ok": True, "email": session.get("email"), "mustChangePassword": False})
    _set_session_cookie(response, request, session)
    return response


@auth_router.post("/api/auth/password/send-code")
async def auth_password_send_code(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = _normalize_email(body.get("email") if isinstance(body, dict) else "")
    if not email:
        return JSONResponse({"ok": False, "error": "email_required"}, status_code=400)
    existing = _users(request).find_user(email=email)
    if existing and existing.get("password_hash"):
        return JSONResponse({"ok": False, "error": "exists"}, status_code=409)
    code = _email_code()
    if not _users(request).save_email_verification(email, code):
        return JSONResponse({"ok": False, "error": "code_store_failed"}, status_code=500)
    if not _send_verification_code(email, code):
        return JSONResponse({"ok": False, "error": "email_unavailable"}, status_code=503)
    return JSONResponse({"ok": True})


@auth_router.post("/api/auth/password/check-code")
async def auth_password_check_code(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = _normalize_email(body.get("email") if isinstance(body, dict) else "")
    code = str(body.get("code") if isinstance(body, dict) else "")
    status = _users(request).check_email_verification(email, code)
    if status == "ok":
        return JSONResponse({"ok": True, "verified": True})
    code_map = {
        "email_required": 400,
        "code_required": 400,
        "code_missing": 400,
        "code_expired": 400,
        "code_invalid": 400,
    }
    return JSONResponse({"ok": False, "error": status}, status_code=code_map.get(status, 400))


@auth_router.post("/api/auth/password/login")
async def auth_password_login(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = _normalize_email(body.get("email") if isinstance(body, dict) else "")
    password = str(body.get("password") if isinstance(body, dict) else "")
    row = _users(request).find_user(email=email)
    if not row or not row.get("password_hash"):
        return JSONResponse({"ok": False, "error": "invalid_credentials"}, status_code=401)
    if not _verify_password(password, str(row.get("password_hash") or "")):
        return JSONResponse({"ok": False, "error": "invalid_credentials"}, status_code=401)
    row = _users(request).login_password_user(email) or row
    session = _session_user(row, "password")
    response = JSONResponse(
        {
            "ok": True,
            "email": session.get("email"),
            "mustChangePassword": bool(row.get("mustChangePassword")),
        }
    )
    _set_session_cookie(response, request, session)
    return response


@auth_router.post("/api/auth/password/forgot")
async def auth_password_forgot(request: Request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = _normalize_email(body.get("email") if isinstance(body, dict) else "")
    if not email:
        return JSONResponse({"ok": True})
    row = _users(request).find_user(email=email)
    if not row or not row.get("password_hash"):
        return JSONResponse({"ok": True})
    temp = _temp_password()
    updated = _users(request).set_user_password(
        row["user_id"],
        _hash_password(temp),
        must_change_password=True,
        email=email,
    )
    if not updated:
        return JSONResponse({"ok": True})
    if not _send_temp_password(email, temp):
        return JSONResponse({"ok": False, "error": "email_unavailable"}, status_code=503)
    return JSONResponse({"ok": True})


@auth_router.post("/api/auth/password/change")
async def auth_password_change(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False, "error": "unauthorized"}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        body = {}
    current_password = str(body.get("currentPassword") if isinstance(body, dict) else "")
    new_password = str(body.get("newPassword") if isinstance(body, dict) else "")
    if len(new_password) < 8:
        return JSONResponse({"ok": False, "error": "password_short"}, status_code=400)
    row = session_user_row(request)
    if not row or not row.get("password_hash"):
        return JSONResponse({"ok": False, "error": "not_found"}, status_code=404)
    if not _verify_password(current_password, str(row.get("password_hash") or "")):
        return JSONResponse({"ok": False, "error": "invalid_current_password"}, status_code=401)
    current = _users(request).set_user_password(
        row["user_id"],
        _hash_password(new_password),
        must_change_password=False,
    )
    if not current:
        return JSONResponse({"ok": False, "error": "not_found"}, status_code=404)
    response = JSONResponse({"ok": True, "mustChangePassword": False})
    _set_session_cookie(response, request, _session_user(current, "password"))
    return response


@auth_router.post("/api/auth/email")
async def auth_save_email(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        body = {}
    email = pick_email(body.get("email") if isinstance(body, dict) else "")
    if not email:
        return JSONResponse({"ok": False}, status_code=400)
    user = _users(request).set_user_email(
        str(session.get("id") or ""),
        email,
        str(session.get("name") or ""),
    )
    if not user:
        return JSONResponse({"ok": False}, status_code=400)
    response = JSONResponse({"ok": True, "email": email})
    _set_session_cookie(
        response,
        request,
        _session_user(user, str(session.get("provider") or user.get("provider") or "")),
    )
    return response


@auth_router.post("/api/auth/terms")
async def auth_accept_terms(request: Request):
    session = read_session(request)
    if not session:
        return JSONResponse({"ok": False}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        body = {}
    accepted = body.get("accepted") if isinstance(body, dict) else False
    if accepted is not True:
        return JSONResponse({"ok": False, "error": "required"}, status_code=400)
    user_id = str(session.get("id") or "")
    if not request.app.state.store.access.accept_terms(user_id):
        return JSONResponse({"ok": False, "error": "identity"}, status_code=400)
    return {"ok": True, "termsAccepted": True, "termsVersion": TERMS_VERSION}


@auth_router.post("/api/auth/logout")
async def auth_logout():
    response = JSONResponse({"ok": True})
    response.delete_cookie(SESSION_COOKIE, path="/")
    response.delete_cookie(OAUTH_COOKIE, path="/")
    return response


def _pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    if len(verifier) > 128:
        verifier = verifier[:128]
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


def _start_oauth(
    request: Request,
    provider: str,
    authorize_url: str,
    extra: dict[str, str],
    redirect_uri: str,
    extra_cookie: dict[str, str] | None = None,
) -> RedirectResponse:
    nxt = _safe_next(request.query_params.get("next"))
    state = secrets.token_urlsafe(32)
    payload = _signer().dumps(
        {
            "state": state,
            "provider": provider,
            "next": nxt,
            "redirect_uri": redirect_uri,
            **(extra_cookie or {}),
        }
    )
    print(f"oauth {provider} redirect_uri={redirect_uri}", flush=True)
    response = RedirectResponse(authorize_url + "?" + urlencode(extra | {"state": state}), status_code=302)
    response.set_cookie(
        OAUTH_COOKIE,
        payload,
        max_age=OAUTH_MAX_AGE,
        httponly=True,
        samesite="lax",
        secure=_cookie_secure(request),
        path="/",
    )
    return response


def _load_oauth_state(
    request: Request, provider: str, state: str | None = None
) -> dict[str, Any] | None:
    raw = request.cookies.get(OAUTH_COOKIE)
    if not raw:
        return None
    try:
        data = _signer().loads(raw, max_age=OAUTH_MAX_AGE)
    except (BadSignature, SignatureExpired):
        return None
    if not isinstance(data, dict) or data.get("provider") != provider:
        return None
    expected = state if state is not None else request.query_params.get("state")
    if data.get("state") != expected:
        return None
    return data


def _oauth_fail(code: str) -> RedirectResponse:
    return RedirectResponse(f"/?oauth_error={code}", status_code=302)


def _oauth_ok(request: Request, user: dict[str, Any], nxt: str) -> RedirectResponse:
    response = RedirectResponse(nxt, status_code=302)
    _set_session_cookie(response, request, user)
    response.delete_cookie(OAUTH_COOKIE, path="/")
    return response


@auth_router.get("/api/auth/oauth/yandex/start")
async def yandex_start(request: Request):
    if not yandex_configured():
        return _oauth_fail("yandex_denied")
    redirect_uri = oauth_redirect_uri(request, "yandex")
    return _start_oauth(
        request,
        "yandex",
        "https://oauth.yandex.ru/authorize",
        {
            "response_type": "code",
            "client_id": os.environ["YANDEX_OAUTH_CLIENT_ID"].strip(),
            "redirect_uri": redirect_uri,
        },
        redirect_uri,
    )


@auth_router.get("/api/auth/oauth/yandex/callback")
async def yandex_callback(request: Request):
    if request.query_params.get("error"):
        return _oauth_fail("yandex_denied")
    packed = _load_oauth_state(request, "yandex")
    if not packed:
        return _oauth_fail("yandex_state")
    code = request.query_params.get("code")
    if not code:
        return _oauth_fail("yandex_denied")
    redirect_uri = packed.get("redirect_uri") or oauth_redirect_uri(request, "yandex")
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            token_res = await client.post(
                "https://oauth.yandex.ru/token",
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "client_id": os.environ["YANDEX_OAUTH_CLIENT_ID"].strip(),
                    "client_secret": os.environ["YANDEX_OAUTH_CLIENT_SECRET"].strip(),
                    "redirect_uri": redirect_uri,
                },
            )
            token_res.raise_for_status()
            access = token_res.json().get("access_token")
            if not access:
                return _oauth_fail("yandex_token")
            info_res = await client.get(
                "https://login.yandex.ru/info",
                params={"format": "json"},
                headers={"Authorization": f"OAuth {access}"},
            )
            info_res.raise_for_status()
            info = info_res.json()
    except Exception:
        return _oauth_fail("yandex_token")
    provider_id = str(info.get("id") or info.get("psuid") or "")
    if not provider_id:
        return _oauth_fail("yandex_profile")
    name = info.get("display_name") or info.get("real_name") or info.get("login") or ""
    email = yandex_email(info)
    print(f"oauth yandex keys={sorted(info.keys())} email_ok={bool(email)}", flush=True)
    user = upsert_user(request, "yandex", provider_id, str(name), email)
    return _oauth_ok(request, user, packed.get("next") or "/?download=1")


@auth_router.get("/api/auth/oauth/vk/start")
async def vk_start(request: Request):
    if not vk_configured():
        return _oauth_fail("vk_denied")
    redirect_uri = oauth_redirect_uri(request, "vk")
    verifier, challenge = _pkce_pair()
    return _start_oauth(
        request,
        "vk",
        "https://id.vk.ru/authorize",
        {
            "response_type": "code",
            "client_id": os.environ["VK_OAUTH_CLIENT_ID"].strip(),
            "redirect_uri": redirect_uri,
            "scope": "email",
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        },
        redirect_uri,
        extra_cookie={"code_verifier": verifier},
    )


def _vk_callback_params(request: Request) -> dict[str, str]:
    raw = request.query_params.get("payload")
    if raw:
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                return {
                    "code": str(data.get("code") or ""),
                    "state": str(data.get("state") or ""),
                    "device_id": str(data.get("device_id") or ""),
                }
        except Exception:
            pass
    return {
        "code": request.query_params.get("code") or "",
        "state": request.query_params.get("state") or "",
        "device_id": request.query_params.get("device_id") or "",
    }


@auth_router.get("/api/auth/oauth/vk/callback")
async def vk_callback(request: Request):
    if request.query_params.get("error"):
        return _oauth_fail("vk_denied")
    params = _vk_callback_params(request)
    packed = _load_oauth_state(request, "vk", state=params.get("state") or None)
    if not packed:
        return _oauth_fail("vk_state")
    code = params.get("code") or ""
    device_id = params.get("device_id") or ""
    verifier = packed.get("code_verifier") or ""
    if not code or not device_id or not verifier:
        return _oauth_fail("vk_denied")
    redirect_uri = packed.get("redirect_uri") or oauth_redirect_uri(request, "vk")
    client_id = os.environ["VK_OAUTH_CLIENT_ID"].strip()
    secret = (
        os.environ.get("VK_OAUTH_CLIENT_SECRET") or os.environ.get("VK_OAUTH_SECRET_KEY") or ""
    ).strip()
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            token_body = {
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "client_id": client_id,
                "device_id": device_id,
                "redirect_uri": redirect_uri,
                "state": packed.get("state") or "",
            }
            if secret:
                token_body["service_token"] = secret
            token_res = await client.post("https://id.vk.ru/oauth2/auth", data=token_body)
            if token_res.status_code >= 400:
                print(f"oauth vk token status={token_res.status_code} {token_res.text[:240]}", flush=True)
            token_res.raise_for_status()
            token = token_res.json()
            access = token.get("access_token")
            user_id = token.get("user_id")
            if not access:
                return _oauth_fail("vk_token")
            info_res = await client.post(
                "https://id.vk.ru/oauth2/user_info",
                data={"access_token": access, "client_id": client_id},
            )
            if not info_res.is_success:
                print(f"oauth vk user_info status={info_res.status_code}", flush=True)
            info = info_res.json() if info_res.is_success else {}
    except Exception as exc:
        print(f"oauth vk token {type(exc).__name__}", flush=True)
        return _oauth_fail("vk_token")
    profile = info.get("user") if isinstance(info.get("user"), dict) else {}
    if not user_id:
        user_id = profile.get("user_id")
    if not user_id:
        return _oauth_fail("vk_token")
    name = f"{profile.get('first_name') or ''} {profile.get('last_name') or ''}".strip()
    email = pick_email(
        profile.get("email"),
        token.get("email"),
        email_from_jwt(token.get("id_token")),
    )
    print(
        f"oauth vk scope={token.get('scope')!r} user_keys={sorted(profile.keys())} email_ok={bool(email)}",
        flush=True,
    )
    user = upsert_user(request, "vk", str(user_id), name, email)
    return _oauth_ok(request, user, packed.get("next") or "/")
