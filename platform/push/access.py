"""Access codes and downloads (SQLite or MySQL)."""

from __future__ import annotations

import json
import os
import secrets
import threading
import uuid
from calendar import monthrange
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from db import DbConn, connect, default_database_url, describe_url

ACCESS_SELECT = "code, purchased_at, expires_at, activated_at, activation_count, slug, user_id, payment_id"
MAX_ACTIVATIONS_PER_USER = 3
DOWNLOAD_SELECT = (
    "payment_id, user_id, slug, kind, status, created_at, downloaded_at, download_count"
)
USER_SELECT = (
    "user_id, email, vk_id, yandex_id, password_hash, name, "
    "must_change_password, created_at, last_login_at"
)
TERMS_VERSION = "1"

SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  user_id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT,
  vk_id TEXT,
  yandex_id TEXT,
  password_hash TEXT,
  name TEXT,
  must_change_password INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  last_login_at TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_vk ON users (vk_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_yandex ON users (yandex_id);

CREATE TABLE IF NOT EXISTS access_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  purchased_at TEXT NOT NULL,
  expires_at TEXT,
  activated_at TEXT,
  activation_count INTEGER NOT NULL DEFAULT 0,
  slug TEXT NOT NULL DEFAULT 'microgreens',
  user_id TEXT,
  payment_id TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_access_user ON access_codes (user_id, slug);

CREATE TABLE IF NOT EXISTS downloads (
  payment_id TEXT PRIMARY KEY,
  user_id TEXT,
  slug TEXT NOT NULL,
  kind TEXT,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  downloaded_at TEXT,
  download_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_dl_user ON downloads (user_id, slug);

CREATE TABLE IF NOT EXISTS user_terms (
  consent_key TEXT PRIMARY KEY,
  user_id TEXT,
  accepted_at TEXT NOT NULL,
  terms_version TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_terms_user ON user_terms (user_id);

CREATE TABLE IF NOT EXISTS email_verifications (
  email TEXT PRIMARY KEY,
  code TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  verified_at TEXT
);
"""

MYSQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  user_id INTEGER PRIMARY KEY AUTO_INCREMENT,
  email VARCHAR(255),
  vk_id VARCHAR(64),
  yandex_id VARCHAR(64),
  password_hash TEXT,
  name VARCHAR(255),
  must_change_password TINYINT NOT NULL DEFAULT 0,
  created_at VARCHAR(64) NOT NULL,
  last_login_at VARCHAR(64),
  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_vk (vk_id),
  UNIQUE KEY uq_users_yandex (yandex_id)
);

CREATE TABLE IF NOT EXISTS access_codes (
  id INTEGER PRIMARY KEY AUTO_INCREMENT,
  code VARCHAR(16) NOT NULL,
  purchased_at VARCHAR(64) NOT NULL,
  expires_at VARCHAR(64),
  activated_at VARCHAR(64),
  activation_count INTEGER NOT NULL DEFAULT 0,
  slug VARCHAR(64) NOT NULL DEFAULT 'microgreens',
  user_id VARCHAR(255),
  payment_id VARCHAR(255),
  UNIQUE KEY uq_access_code (code),
  UNIQUE KEY uq_access_payment (payment_id),
  KEY idx_access_user (user_id, slug)
);

CREATE TABLE IF NOT EXISTS downloads (
  payment_id VARCHAR(255) PRIMARY KEY,
  user_id VARCHAR(255),
  slug VARCHAR(64) NOT NULL,
  kind VARCHAR(16),
  status VARCHAR(32) NOT NULL,
  created_at VARCHAR(64) NOT NULL,
  downloaded_at VARCHAR(64),
  download_count INTEGER NOT NULL DEFAULT 0,
  KEY idx_dl_user (user_id, slug)
);

CREATE TABLE IF NOT EXISTS user_terms (
  consent_key VARCHAR(255) PRIMARY KEY,
  user_id VARCHAR(255),
  accepted_at VARCHAR(64) NOT NULL,
  terms_version VARCHAR(32) NOT NULL,
  KEY idx_terms_user (user_id)
);

CREATE TABLE IF NOT EXISTS email_verifications (
  email VARCHAR(255) PRIMARY KEY,
  code VARCHAR(16) NOT NULL,
  sent_at VARCHAR(64) NOT NULL,
  expires_at VARCHAR(64) NOT NULL,
  verified_at VARCHAR(64)
);
"""


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def _now_iso() -> str:
    return _now().isoformat()


def _norm_email(value: Any) -> str:
    text = str(value or "").strip().lower()
    if "@" not in text or " " in text:
        return ""
    local, _, domain = text.partition("@")
    return text if local and "." in domain else ""


def _blank_to_none(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _row_value(row: Any, key: str, index: int | None = None) -> Any:
    if row is None:
        return None
    if isinstance(row, dict):
        return row.get(key)
    try:
        return row[key]
    except (KeyError, IndexError, TypeError):
        if index is None:
            return None
        try:
            return row[index]
        except (KeyError, IndexError, TypeError):
            return None


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).replace(microsecond=0)


def paid_period_months() -> int:
    raw = (os.environ.get("PAID_PERIOD") or "12").strip()
    try:
        months = int(float(raw.replace(",", ".")))
    except ValueError:
        months = 12
    return max(1, months)


def pending_payment_ttl_seconds() -> int:
    """How long a Yookassa payment row stays "pending" for a user.

    If the user leaves the checkout and comes back later, we still want to
    allow retrying payment (frontend shows spinner while any `pending` exists).
    """
    raw = (os.environ.get("PAY_PENDING_TTL_MIN") or "10").strip()
    try:
        minutes = int(float(raw.replace(",", ".")))
    except ValueError:
        minutes = 10
    minutes = max(1, minutes)
    return minutes * 60


def _ru_plural(n: int, one: str, few: str, many: str) -> str:
    n = abs(n) % 100
    if 11 <= n <= 14:
        return many
    last = n % 10
    if last == 1:
        return one
    if 2 <= last <= 4:
        return few
    return many


def paid_period_label(months: int | None = None) -> str:
    n = paid_period_months() if months is None else max(1, months)
    if n % 12 == 0:
        years = n // 12
        return f"{years} {_ru_plural(years, 'год', 'года', 'лет')}"
    return f"{n} {_ru_plural(n, 'месяц', 'месяца', 'месяцев')}"


def add_months(dt: datetime, months: int | None = None) -> datetime:
    delta = paid_period_months() if months is None else months
    month_index = dt.month - 1 + delta
    year = dt.year + month_index // 12
    month = month_index % 12 + 1
    day = min(dt.day, monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


def expires_iso(purchased_at: str | None = None) -> str:
    start = parse_iso(purchased_at) or _now()
    return add_months(start).isoformat()


def is_active(row: dict[str, Any] | None) -> bool:
    if not row:
        return False
    activated = parse_iso(row.get("activated_at"))
    expires = parse_iso(row.get("expires_at"))
    if activated:
        end = expires or add_months(activated)
        return _now() < end
    if expires and _now() >= expires:
        return False
    return True


def _as_dict(row: Any) -> dict[str, Any] | None:
    if row is None:
        return None
    if isinstance(row, dict):
        return dict(row)
    return {key: row[key] for key in row.keys()}


def _row_dict(row: Any) -> dict[str, Any] | None:
    data = _as_dict(row)
    if not data:
        return None
    if "code" in data and not data.get("expires_at") and data.get("activated_at"):
        data["expires_at"] = expires_iso(data.get("activated_at"))
    if "download_count" in data:
        try:
            data["download_count"] = int(data.get("download_count") or 0)
        except (TypeError, ValueError):
            data["download_count"] = 0
    if "activation_count" in data:
        try:
            data["activation_count"] = max(0, int(data.get("activation_count") or 0))
        except (TypeError, ValueError):
            data["activation_count"] = 0
    return data


def download_count_of(row: dict[str, Any] | None) -> int:
    if not row:
        return 0
    try:
        return max(0, int(row.get("download_count") or 0))
    except (TypeError, ValueError):
        return 0


class AccessDB:
    def __init__(self, url: str | Path | None = None, data_dir: str | Path | None = None) -> None:
        if isinstance(url, Path):
            url = f"sqlite:///{url.resolve().as_posix()}"
        self.url = (str(url).strip() if url else "") or default_database_url()
        self.data_dir = Path(
            data_dir or os.environ.get("DATA_DIR") or Path(__file__).resolve().parent / "data"
        )
        self._lock = threading.Lock()
        print(f"Access DB: {describe_url(self.url)}", flush=True)
        with self._connect() as db:
            self._migrate_payments_table(db)
            db.executescript(MYSQL_SCHEMA if db.kind == "mysql" else SQLITE_SCHEMA)
            cols = self._column_names(db, "access_codes")
            col_type = "VARCHAR(64)" if db.kind == "mysql" else "TEXT"
            if "expires_at" not in cols:
                db.execute(f"ALTER TABLE access_codes ADD COLUMN expires_at {col_type}")
            if "activated_at" not in cols:
                db.execute(f"ALTER TABLE access_codes ADD COLUMN activated_at {col_type}")
            if "activation_count" not in cols:
                db.execute(
                    "ALTER TABLE access_codes ADD COLUMN activation_count INTEGER NOT NULL DEFAULT 0"
                )
                db.execute(
                    """
                    UPDATE access_codes
                    SET activation_count = 1
                    WHERE activation_count = 0
                      AND activated_at IS NOT NULL
                      AND activated_at != ''
                    """
                )
            self._ensure_download_columns(db, col_type)
            if db.kind == "mysql":
                self._ensure_mysql_indexes(db)
            self._migrate_users_json(db)
            self._backfill_users_from_legacy(db)
            self._drop_legacy_identity_columns(db)
            db.commit()

    def _connect(self) -> DbConn:
        return connect(self.url)

    def _ensure_mysql_indexes(self, db: DbConn) -> None:
        # CREATE INDEX IF NOT EXISTS is not supported on older MySQL.
        for sql in (
            "CREATE UNIQUE INDEX uq_users_email ON users (email)",
            "CREATE UNIQUE INDEX uq_users_vk ON users (vk_id)",
            "CREATE UNIQUE INDEX uq_users_yandex ON users (yandex_id)",
            "CREATE INDEX idx_access_user ON access_codes (user_id, slug)",
            "CREATE INDEX idx_dl_user ON downloads (user_id, slug)",
            "CREATE INDEX idx_terms_user ON user_terms (user_id)",
        ):
            try:
                db.execute(sql)
            except Exception as exc:
                msg = str(exc).lower()
                if "duplicate" in msg or "1061" in msg or "already exists" in msg:
                    continue
                print(f"mysql index: {exc}", flush=True)

    def _table_exists(self, db: DbConn, name: str) -> bool:
        if db.kind == "mysql":
            row = db.execute(
                """
                SELECT 1 FROM INFORMATION_SCHEMA.TABLES
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                """,
                (name,),
            ).fetchone()
            return row is not None
        row = db.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            (name,),
        ).fetchone()
        return row is not None

    def _migrate_payments_table(self, db: DbConn) -> None:
        if self._table_exists(db, "downloads") or not self._table_exists(db, "payments"):
            return
        if db.kind == "mysql":
            db.execute("RENAME TABLE payments TO downloads")
        else:
            db.execute("ALTER TABLE payments RENAME TO downloads")

    def _ensure_download_columns(self, db: DbConn, col_type: str) -> None:
        cols = self._column_names(db, "downloads")
        if not cols:
            return
        extra = {
            "kind": "VARCHAR(16)" if db.kind == "mysql" else "TEXT",
            "downloaded_at": col_type,
            "download_count": "INTEGER NOT NULL DEFAULT 0",
        }
        for name, sql_type in extra.items():
            if name not in cols:
                db.execute(f"ALTER TABLE downloads ADD COLUMN {name} {sql_type}")
        cols = self._column_names(db, "downloads")
        if "download_count" in cols:
            db.execute(
                """
                UPDATE downloads
                SET download_count = 1
                WHERE downloaded_at IS NOT NULL AND downloaded_at != ''
                  AND COALESCE(download_count, 0) = 0
                """
            )
        # Access dates live only on access_codes — drop duplicates from downloads.
        for obsolete in (
            "apk_downloaded_at",
            "pwa_downloaded_at",
            "paid_at",
            "activated_at",
        ):
            if obsolete in cols:
                self._drop_column(db, "downloads", obsolete)

    def _drop_index(self, db: DbConn, name: str, table: str) -> None:
        try:
            if db.kind == "mysql":
                db.execute(f"DROP INDEX {name} ON {table}")
            else:
                db.execute(f"DROP INDEX IF EXISTS {name}")
        except Exception:
            pass

    def _drop_column(self, db: DbConn, table: str, column: str) -> None:
        cols = self._column_names(db, table)
        if column not in cols:
            return
        try:
            db.execute(f"ALTER TABLE {table} DROP COLUMN {column}")
        except Exception as exc:
            print(f"{table} drop {column}: {exc}", flush=True)

    def _drop_legacy_identity_columns(self, db: DbConn) -> None:
        for name, table in (
            ("idx_access_email", "access_codes"),
            ("idx_dl_email", "downloads"),
            ("idx_terms_email", "user_terms"),
        ):
            self._drop_index(db, name, table)
        self._drop_column(db, "access_codes", "email")
        self._drop_column(db, "downloads", "email")
        self._drop_column(db, "downloads", "app_name")
        self._drop_column(db, "user_terms", "email")

    def _column_names(self, db: DbConn, table: str) -> set[str]:
        if db.kind == "mysql":
            rows = db.execute(
                """
                SELECT COLUMN_NAME AS name
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                """,
                (table,),
            ).fetchall()
            return {(row["name"] if isinstance(row, dict) else row[0]) for row in rows}
        rows = db.execute(f"PRAGMA table_info({table})").fetchall()
        names: set[str] = set()
        for row in rows:
            if isinstance(row, dict):
                names.add(str(row.get("name") or ""))
            else:
                names.add(str(row[1]))
        return names

    def _user_dict(self, row: Any, provider: str | None = None) -> dict[str, Any] | None:
        data = _as_dict(row)
        if not data:
            return None
        try:
            uid = int(data.get("user_id"))
        except (TypeError, ValueError):
            return None
        email = str(data.get("email") or "")
        yandex_id = str(data.get("yandex_id") or "")
        vk_id = str(data.get("vk_id") or "")
        password_hash = str(data.get("password_hash") or "")
        if provider:
            resolved = provider
        elif password_hash:
            resolved = "password"
        elif yandex_id:
            resolved = "yandex"
        elif vk_id:
            resolved = "vk"
        else:
            resolved = "password"
        return {
            "user_id": uid,
            "id": str(uid),
            "email": email,
            "vk_id": vk_id,
            "yandex_id": yandex_id,
            "password_hash": password_hash,
            "name": str(data.get("name") or ""),
            "mustChangePassword": bool(data.get("must_change_password")),
            "createdAt": str(data.get("created_at") or ""),
            "lastLoginAt": str(data.get("last_login_at") or ""),
            "provider": resolved,
            "hasPassword": bool(password_hash),
        }

    def _lookup_user_keys(
        self,
        user_id: str = "",
        email: str = "",
        yandex_id: str = "",
        vk_id: str = "",
    ) -> dict[str, Any]:
        uid = str(user_id or "").strip()
        mail = _norm_email(email)
        yid = str(yandex_id or "").strip()
        vid = str(vk_id or "").strip()
        numeric: int | None = None
        if uid.isdigit():
            numeric = int(uid)
        elif uid.startswith("yandex:"):
            yid = yid or uid.split(":", 1)[1]
        elif uid.startswith("vk:"):
            vid = vid or uid.split(":", 1)[1]
        elif uid.startswith("email:"):
            mail = mail or _norm_email(uid.split(":", 1)[1])
        return {"user_id": numeric, "email": mail, "yandex_id": yid, "vk_id": vid}

    def _get_user_row(
        self,
        db: DbConn,
        user_id: str | int = "",
        email: str = "",
        yandex_id: str = "",
        vk_id: str = "",
    ) -> dict[str, Any] | None:
        keys = self._lookup_user_keys(str(user_id or ""), email, yandex_id, vk_id)
        queries: list[tuple[str, tuple[Any, ...]]] = []
        if keys["user_id"] is not None:
            queries.append((f"SELECT {USER_SELECT} FROM users WHERE user_id = ?", (keys["user_id"],)))
        if keys["yandex_id"]:
            queries.append((f"SELECT {USER_SELECT} FROM users WHERE yandex_id = ?", (keys["yandex_id"],)))
        if keys["vk_id"]:
            queries.append((f"SELECT {USER_SELECT} FROM users WHERE vk_id = ?", (keys["vk_id"],)))
        if keys["email"]:
            queries.append((f"SELECT {USER_SELECT} FROM users WHERE email = ?", (keys["email"],)))
        for sql, params in queries:
            row = self._user_dict(db.execute(sql, params).fetchone())
            if row:
                return row
        return None

    def _insert_user(
        self,
        db: DbConn,
        *,
        email: str = "",
        vk_id: str = "",
        yandex_id: str = "",
        password_hash: str = "",
        name: str = "",
        must_change_password: bool = False,
    ) -> dict[str, Any]:
        now = _now_iso()
        cur = db.execute(
            """
            INSERT INTO users (
              email, vk_id, yandex_id, password_hash, name,
              must_change_password, created_at, last_login_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                _norm_email(email) or None,
                _blank_to_none(vk_id),
                _blank_to_none(yandex_id),
                _blank_to_none(password_hash),
                (name or "").strip(),
                1 if must_change_password else 0,
                now,
                now,
            ),
        )
        uid = int(getattr(cur, "lastrowid", 0) or 0)
        if not uid:
            raw = db.execute(
                "SELECT LAST_INSERT_ID() AS id"
                if db.kind == "mysql"
                else "SELECT last_insert_rowid() AS id"
            ).fetchone()
            uid = int(_row_value(raw, "id", 0) or 0)
        row = self._get_user_row(db, user_id=uid)
        if not row:
            raise RuntimeError("failed to create user")
        return row

    def _insert_user_safe(self, db: DbConn, **kwargs: Any) -> dict[str, Any] | None:
        try:
            return self._insert_user(db, **kwargs)
        except Exception as exc:
            print(f"insert user: {exc}", flush=True)
            return self._get_user_row(
                db,
                email=str(kwargs.get("email") or ""),
                yandex_id=str(kwargs.get("yandex_id") or ""),
                vk_id=str(kwargs.get("vk_id") or ""),
            )

    def _remap_user_refs(self, db: DbConn, old_id: str, new_id: int) -> None:
        old = str(old_id or "").strip()
        new = str(int(new_id))
        if not old or old == new:
            return
        for table in ("access_codes", "downloads", "user_terms"):
            db.execute(f"UPDATE {table} SET user_id = ? WHERE user_id = ?", (new, old))

    def _link_rows_by_email(self, db: DbConn, email: str, user_id: int) -> None:
        mail = _norm_email(email)
        if not mail:
            return
        uid = str(int(user_id))
        for table in ("access_codes", "downloads", "user_terms"):
            if "email" not in self._column_names(db, table):
                continue
            db.execute(
                f"""
                UPDATE {table}
                SET user_id = ?
                WHERE lower(email) = ? AND (user_id IS NULL OR user_id = '')
                """,
                (uid, mail),
            )

    def _migrate_users_json(self, db: DbConn) -> None:
        path = self.data_dir / "users.json"
        if not path.exists():
            return
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            raw = {}
        if not isinstance(raw, dict):
            return
        imported = 0
        for old_id, item in raw.items():
            if not isinstance(item, dict):
                continue
            provider = str(item.get("provider") or "")
            provider_id = str(item.get("providerId") or "")
            email = _norm_email(item.get("email"))
            yandex_id = provider_id if provider == "yandex" else ""
            vk_id = provider_id if provider == "vk" else ""
            text_id = str(old_id)
            if text_id.startswith("yandex:"):
                yandex_id = text_id.split(":", 1)[-1]
            elif text_id.startswith("vk:"):
                vk_id = text_id.split(":", 1)[-1]
            elif text_id.startswith("email:"):
                email = email or _norm_email(text_id.split(":", 1)[-1])
            existing = self._get_user_row(
                db,
                email=email,
                yandex_id=yandex_id,
                vk_id=vk_id,
            )
            password_hash = str(item.get("passwordHash") or "")
            name = str(item.get("name") or "")
            must_change = bool(item.get("mustChangePassword"))
            now = _now_iso()
            if existing:
                uid = int(existing["user_id"])
                db.execute(
                    """
                    UPDATE users
                    SET email = COALESCE(NULLIF(?, ''), email),
                        vk_id = COALESCE(NULLIF(?, ''), vk_id),
                        yandex_id = COALESCE(NULLIF(?, ''), yandex_id),
                        password_hash = COALESCE(NULLIF(?, ''), password_hash),
                        name = CASE WHEN ? != '' THEN ? ELSE name END,
                        must_change_password = CASE WHEN ? = 1 THEN 1 ELSE must_change_password END,
                        last_login_at = COALESCE(NULLIF(?, ''), last_login_at)
                    WHERE user_id = ?
                    """,
                    (
                        email,
                        vk_id,
                        yandex_id,
                        password_hash,
                        name,
                        name,
                        1 if must_change else 0,
                        str(item.get("lastLoginAt") or ""),
                        uid,
                    ),
                )
                row = self._get_user_row(db, user_id=uid) or existing
            else:
                row = self._insert_user_safe(
                    db,
                    email=email,
                    vk_id=vk_id,
                    yandex_id=yandex_id,
                    password_hash=password_hash,
                    name=name or (email.split("@", 1)[0] if email else ""),
                    must_change_password=must_change,
                )
                if not row:
                    continue
                if item.get("createdAt"):
                    db.execute(
                        "UPDATE users SET created_at = ? WHERE user_id = ?",
                        (str(item.get("createdAt") or now), row["user_id"]),
                    )
                if item.get("lastLoginAt"):
                    db.execute(
                        "UPDATE users SET last_login_at = ? WHERE user_id = ?",
                        (str(item.get("lastLoginAt") or now), row["user_id"]),
                    )
            self._remap_user_refs(db, text_id, int(row["user_id"]))
            if email:
                self._link_rows_by_email(db, email, int(row["user_id"]))
            imported += 1
        bak = path.with_name("users.json.migrated")
        try:
            if bak.exists():
                bak.unlink()
            path.replace(bak)
        except Exception as exc:
            print(f"users.json migrate rename: {exc}", flush=True)
        if imported:
            print(f"migrated {imported} users from users.json", flush=True)

    def _backfill_users_from_legacy(self, db: DbConn) -> None:
        for table in ("access_codes", "downloads", "user_terms"):
            cols = self._column_names(db, table)
            if "user_id" not in cols:
                continue
            select = "SELECT DISTINCT user_id"
            if "email" in cols:
                select = "SELECT DISTINCT email, user_id"
            try:
                rows = db.execute(f"{select} FROM {table}").fetchall()
            except Exception:
                continue
            for raw in rows:
                data = _as_dict(raw) or {}
                mail = _norm_email(data.get("email")) if "email" in cols else ""
                old_uid = str(data.get("user_id") or "").strip()
                row = self._get_user_row(db, user_id=old_uid, email=mail)
                if not row and (mail or old_uid.startswith("yandex:") or old_uid.startswith("vk:")):
                    yandex_id = old_uid.split(":", 1)[-1] if old_uid.startswith("yandex:") else ""
                    vk_id = old_uid.split(":", 1)[-1] if old_uid.startswith("vk:") else ""
                    row = self._insert_user_safe(
                        db,
                        email=mail,
                        yandex_id=yandex_id,
                        vk_id=vk_id,
                        name=mail.split("@", 1)[0] if mail else "",
                    )
                if not row:
                    continue
                uid = int(row["user_id"])
                if old_uid and not old_uid.isdigit():
                    self._remap_user_refs(db, old_uid, uid)
                if mail:
                    self._link_rows_by_email(db, mail, uid)

    def find_user(
        self,
        user_id: str | int = "",
        email: str = "",
        yandex_id: str = "",
        vk_id: str = "",
    ) -> dict[str, Any] | None:
        with self._lock:
            db = self._connect()
            try:
                return self._get_user_row(db, user_id=user_id, email=email, yandex_id=yandex_id, vk_id=vk_id)
            finally:
                db.close()

    def _canonical_uid(self, db: DbConn, user_id: str = "", email: str = "") -> str:
        row = self._get_user_row(db, user_id=user_id, email=email)
        if row:
            return str(int(row["user_id"]))
        if str(user_id or "").strip().isdigit():
            return str(int(user_id))
        return ""

    def ensure_user(self, user_id: str = "", email: str = "", name: str = "") -> dict[str, Any] | None:
        mail = _norm_email(email)
        with self._lock:
            db = self._connect()
            try:
                row = self._get_user_row(db, user_id=user_id, email=mail)
                if not row and mail:
                    row = self._insert_user(
                        db,
                        email=mail,
                        name=name or mail.split("@", 1)[0],
                    )
                    self._link_rows_by_email(db, mail, int(row["user_id"]))
                if row:
                    db.commit()
                return row
            finally:
                db.close()

    def upsert_oauth_user(
        self,
        provider: str,
        provider_id: str,
        name: str,
        email: str = "",
    ) -> dict[str, Any]:
        yandex_id = provider_id if provider == "yandex" else ""
        vk_id = provider_id if provider == "vk" else ""
        mail = _norm_email(email)
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                row = None
                if yandex_id:
                    row = self._get_user_row(db, yandex_id=yandex_id)
                if not row and vk_id:
                    row = self._get_user_row(db, vk_id=vk_id)
                if not row and mail:
                    row = self._get_user_row(db, email=mail)
                    if row:
                        taken_yandex = str(row.get("yandex_id") or "")
                        taken_vk = str(row.get("vk_id") or "")
                        if yandex_id and taken_yandex and taken_yandex != yandex_id:
                            row = None
                            mail = ""
                        elif vk_id and taken_vk and taken_vk != vk_id:
                            row = None
                            mail = ""
                if row:
                    uid = int(row["user_id"])
                    db.execute(
                        """
                        UPDATE users
                        SET email = COALESCE(NULLIF(?, ''), email),
                            vk_id = COALESCE(NULLIF(?, ''), vk_id),
                            yandex_id = COALESCE(NULLIF(?, ''), yandex_id),
                            name = CASE WHEN ? != '' THEN ? ELSE name END,
                            last_login_at = ?
                        WHERE user_id = ?
                        """,
                        (mail, vk_id, yandex_id, name, name, now, uid),
                    )
                else:
                    row = self._insert_user(
                        db,
                        email=mail,
                        vk_id=vk_id,
                        yandex_id=yandex_id,
                        name=name,
                    )
                    uid = int(row["user_id"])
                if mail:
                    self._link_rows_by_email(db, mail, uid)
                db.commit()
                return self._get_user_row(db, user_id=uid) or row
            finally:
                db.close()

    def register_password_user(self, email: str, password_hash: str) -> tuple[str | None, dict[str, Any] | None]:
        mail = _norm_email(email)
        if not mail:
            return "email_required", None
        with self._lock:
            db = self._connect()
            try:
                existing = self._get_user_row(db, email=mail)
                if existing and existing.get("password_hash"):
                    return "exists", None
                now = _now_iso()
                if existing:
                    db.execute(
                        """
                        UPDATE users
                        SET password_hash = ?, must_change_password = 0, last_login_at = ?
                        WHERE user_id = ?
                        """,
                        (password_hash, now, existing["user_id"]),
                    )
                    uid = int(existing["user_id"])
                else:
                    row = self._insert_user(
                        db,
                        email=mail,
                        password_hash=password_hash,
                        name=mail.split("@", 1)[0],
                    )
                    uid = int(row["user_id"])
                self._link_rows_by_email(db, mail, uid)
                db.commit()
                user = self._get_user_row(db, user_id=uid)
                if user:
                    user["provider"] = "password"
                return None, user
            finally:
                db.close()

    def login_password_user(self, email: str) -> dict[str, Any] | None:
        mail = _norm_email(email)
        if not mail:
            return None
        with self._lock:
            db = self._connect()
            try:
                row = self._get_user_row(db, email=mail)
                if not row or not row.get("password_hash"):
                    return None
                db.execute(
                    "UPDATE users SET last_login_at = ? WHERE user_id = ?",
                    (_now_iso(), row["user_id"]),
                )
                db.commit()
                row["provider"] = "password"
                return row
            finally:
                db.close()

    def set_user_password(
        self,
        user_id: str | int,
        password_hash: str,
        *,
        must_change_password: bool | None = None,
        email: str = "",
    ) -> dict[str, Any] | None:
        with self._lock:
            db = self._connect()
            try:
                row = self._get_user_row(db, user_id=user_id, email=email)
                if not row:
                    return None
                flag = row.get("mustChangePassword") if must_change_password is None else must_change_password
                db.execute(
                    """
                    UPDATE users
                    SET password_hash = ?, must_change_password = ?
                    WHERE user_id = ?
                    """,
                    (password_hash, 1 if flag else 0, row["user_id"]),
                )
                db.commit()
                user = self._get_user_row(db, user_id=row["user_id"])
                if user:
                    user["provider"] = "password"
                return user
            finally:
                db.close()

    def set_user_email(self, user_id: str | int, email: str, name: str = "") -> dict[str, Any] | None:
        mail = _norm_email(email)
        if not mail:
            return None
        with self._lock:
            db = self._connect()
            try:
                row = self._get_user_row(db, user_id=user_id)
                if not row:
                    return None
                db.execute(
                    """
                    UPDATE users
                    SET email = ?, name = CASE WHEN ? != '' THEN ? ELSE name END
                    WHERE user_id = ?
                    """,
                    (mail, name, name, row["user_id"]),
                )
                self._link_rows_by_email(db, mail, int(row["user_id"]))
                db.commit()
                return self._get_user_row(db, user_id=row["user_id"])
            finally:
                db.close()

    def save_email_verification(self, email: str, code: str, ttl_minutes: int = 15) -> bool:
        mail = _norm_email(email)
        digits = "".join(ch for ch in str(code or "") if ch.isdigit())
        if not mail or len(digits) != 6:
            return False
        now = _now()
        expires = (now + timedelta(minutes=max(1, ttl_minutes))).isoformat()
        sent_at = now.isoformat()
        with self._lock:
            db = self._connect()
            try:
                if db.kind == "mysql":
                    db.execute(
                        """
                        INSERT INTO email_verifications (email, code, sent_at, expires_at, verified_at)
                        VALUES (?, ?, ?, ?, NULL)
                        ON DUPLICATE KEY UPDATE
                          code = VALUES(code),
                          sent_at = VALUES(sent_at),
                          expires_at = VALUES(expires_at),
                          verified_at = NULL
                        """,
                        (mail, digits, sent_at, expires),
                    )
                else:
                    db.execute(
                        """
                        INSERT INTO email_verifications (email, code, sent_at, expires_at, verified_at)
                        VALUES (?, ?, ?, ?, NULL)
                        ON CONFLICT(email) DO UPDATE SET
                          code = excluded.code,
                          sent_at = excluded.sent_at,
                          expires_at = excluded.expires_at,
                          verified_at = NULL
                        """,
                        (mail, digits, sent_at, expires),
                    )
                db.commit()
                return True
            finally:
                db.close()

    def check_email_verification(self, email: str, code: str) -> str:
        mail = _norm_email(email)
        digits = "".join(ch for ch in str(code or "") if ch.isdigit())
        if not mail:
            return "email_required"
        if len(digits) != 6:
            return "code_required"
        with self._lock:
            db = self._connect()
            try:
                row = _row_dict(
                    db.execute(
                        """
                        SELECT email, code, sent_at, expires_at, verified_at
                        FROM email_verifications
                        WHERE email = ?
                        """,
                        (mail,),
                    ).fetchone()
                )
                if not row:
                    return "code_missing"
                expires = parse_iso(str(row.get("expires_at") or ""))
                if not expires or expires <= _now():
                    return "code_expired"
                if str(row.get("code") or "") != digits:
                    return "code_invalid"
                now = _now_iso()
                db.execute(
                    "UPDATE email_verifications SET verified_at = ? WHERE email = ?",
                    (now, mail),
                )
                db.commit()
                return "ok"
            finally:
                db.close()

    def consume_verified_email(self, email: str) -> bool:
        mail = _norm_email(email)
        if not mail:
            return False
        with self._lock:
            db = self._connect()
            try:
                row = _row_dict(
                    db.execute(
                        """
                        SELECT email, expires_at, verified_at
                        FROM email_verifications
                        WHERE email = ?
                        """,
                        (mail,),
                    ).fetchone()
                )
                if not row:
                    return False
                expires = parse_iso(str(row.get("expires_at") or ""))
                verified = parse_iso(str(row.get("verified_at") or ""))
                if not expires or expires <= _now() or not verified:
                    return False
                db.execute("DELETE FROM email_verifications WHERE email = ?", (mail,))
                db.commit()
                return True
            finally:
                db.close()

    def _latest(self, db: DbConn, user_id: str, slug: str, email: str = "") -> dict[str, Any] | None:
        uid = self._canonical_uid(db, user_id, email)
        if not uid:
            return None
        return _row_dict(
            db.execute(
                f"""
                SELECT {ACCESS_SELECT}
                FROM access_codes
                WHERE user_id = ? AND slug = ?
                ORDER BY id DESC LIMIT 1
                """,
                (uid, slug),
            ).fetchone()
        )

    def find(self, user_id: str = "", email: str = "", slug: str = "microgreens") -> dict[str, Any] | None:
        slug = slug or "microgreens"
        with self._lock:
            db = self._connect()
            try:
                row = self._latest(db, user_id, slug, email)
            finally:
                db.close()
        return row if is_active(row) else None

    def lookup_code(self, code: str, slug: str = "microgreens") -> dict[str, Any] | None:
        digits = "".join(ch for ch in (code or "") if ch.isdigit())
        if len(digits) != 6:
            return None
        slug = slug or "microgreens"
        with self._lock:
            db = self._connect()
            try:
                return _row_dict(
                    db.execute(
                        f"""
                        SELECT {ACCESS_SELECT}
                        FROM access_codes
                        WHERE code = ? AND slug = ?
                        ORDER BY id DESC LIMIT 1
                        """,
                        (digits, slug),
                    ).fetchone()
                )
            finally:
                db.close()

    def activate_code(
        self,
        code: str,
        email: str,
        slug: str = "microgreens",
        *,
        record: bool = True,
    ) -> tuple[str | None, dict[str, Any] | None]:
        digits = "".join(ch for ch in (code or "") if ch.isdigit())
        mail = (email or "").strip()
        if len(digits) != 6 or "@" not in mail:
            return "invalid", None
        row = self.lookup_code(digits, slug)
        if not row:
            return "invalid", None
        stored = ""
        owner = self.find_user(user_id=str(row.get("user_id") or ""), email=mail)
        if owner and owner.get("email"):
            stored = str(owner.get("email") or "")
        if stored.lower() != mail.lower():
            return "mismatch", None
        if row.get("activated_at") and not is_active(row):
            return "expired", row
        if not is_active(row):
            return "expired", row
        slug = slug or "microgreens"
        # Status check (app launch) must not consume an activation slot.
        if not record:
            if row.get("activated_at") and not row.get("expires_at"):
                row["expires_at"] = expires_iso(str(row.get("activated_at")))
            return None, row
        # Already activated — keep first activation dates, count this use.
        if row.get("activated_at"):
            with self._lock:
                db = self._connect()
                try:
                    if self._user_activation_total(db, row, slug) >= MAX_ACTIVATIONS_PER_USER:
                        db.commit()
                        return "limit", row
                    fresh = self._increment_activation(db, digits, slug)
                    db.commit()
                finally:
                    db.close()
            if fresh:
                if not fresh.get("expires_at"):
                    fresh["expires_at"] = expires_iso(str(fresh.get("activated_at")))
                return None, fresh
            if not row.get("expires_at"):
                row["expires_at"] = expires_iso(str(row.get("activated_at")))
            return None, row
        activated_at = _now_iso()
        existing_exp = parse_iso(row.get("expires_at"))
        if existing_exp and existing_exp > _now():
            expires_at = existing_exp.isoformat()
        else:
            expires_at = expires_iso(activated_at)
        with self._lock:
            db = self._connect()
            try:
                if self._user_activation_total(db, row, slug) >= MAX_ACTIVATIONS_PER_USER:
                    db.commit()
                    return "limit", row
                cur = db.execute(
                    """
                    UPDATE access_codes
                    SET activated_at = ?, expires_at = ?,
                        activation_count = COALESCE(activation_count, 0) + 1
                    WHERE code = ? AND slug = ? AND activated_at IS NULL
                    """,
                    (activated_at, expires_at, digits, slug),
                )
                # Another request may have activated first — count this use too.
                if not cur.rowcount:
                    if self._user_activation_total(db, row, slug) >= MAX_ACTIVATIONS_PER_USER:
                        db.commit()
                        return "limit", row
                    fresh = self._increment_activation(db, digits, slug)
                    db.commit()
                    if fresh and fresh.get("activated_at"):
                        if not fresh.get("expires_at"):
                            fresh["expires_at"] = expires_iso(str(fresh.get("activated_at")))
                        return None, fresh
                db.commit()
                fresh = self._lookup_code_row(db, digits, slug)
            finally:
                db.close()
        if fresh:
            return None, fresh
        row["activated_at"] = activated_at
        row["expires_at"] = expires_at
        row["activation_count"] = int(row.get("activation_count") or 0) + 1
        return None, row

    def _user_activation_total(
        self, db: DbConn, row: dict[str, Any], slug: str
    ) -> int:
        """Activations billed to this purchaser. Expired older codes do not count."""
        uid = str(row.get("user_id") or "").strip()
        current = str(row.get("code") or "")
        if not uid:
            return int(row.get("activation_count") or 0)
        total = 0
        for raw in db.execute(
            f"""
            SELECT {ACCESS_SELECT}
            FROM access_codes
            WHERE user_id = ? AND slug = ?
            """,
            (uid, slug),
        ).fetchall():
            item = _row_dict(raw)
            if not item:
                continue
            if str(item.get("code") or "") != current and not is_active(item):
                continue
            total += int(item.get("activation_count") or 0)
        return total

    def _lookup_code_row(self, db: DbConn, digits: str, slug: str) -> dict[str, Any] | None:
        return _row_dict(
            db.execute(
                f"""
                SELECT {ACCESS_SELECT}
                FROM access_codes
                WHERE code = ? AND slug = ?
                ORDER BY id DESC LIMIT 1
                """,
                (digits, slug),
            ).fetchone()
        )

    def _increment_activation(
        self, db: DbConn, digits: str, slug: str
    ) -> dict[str, Any] | None:
        db.execute(
            """
            UPDATE access_codes
            SET activation_count = COALESCE(activation_count, 0) + 1
            WHERE code = ? AND slug = ?
            """,
            (digits, slug),
        )
        return self._lookup_code_row(db, digits, slug)

    def record_download(
        self,
        user_id: str,
        slug: str,
        kind: str,
    ) -> int:
        slug = slug or "microgreens"
        kind = "apk" if str(kind).lower() == "apk" else "pwa"
        owner = self.find_user(user_id=user_id)
        uid = str(int(owner["user_id"])) if owner else str(user_id or "")
        if not uid:
            return 0
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                row = self._find_download(db, uid, slug)
                if row:
                    count = download_count_of(row)
                    prev = parse_iso(str(row.get("downloaded_at") or ""))
                    same_kind = str(row.get("kind") or "") == kind
                    recent = prev is not None and (_now() - prev).total_seconds() < 20
                    bump = not (same_kind and recent)
                    if bump:
                        count += 1
                    db.execute(
                        """
                        UPDATE downloads
                        SET user_id = CASE WHEN user_id IS NULL OR user_id = '' THEN ? ELSE user_id END,
                            kind = ?,
                            downloaded_at = ?,
                            download_count = ?
                        WHERE payment_id = ?
                        """,
                        (uid, kind, now, count, row["payment_id"]),
                    )
                else:
                    count = 1
                    db.execute(
                        """
                        INSERT INTO downloads (
                          payment_id, user_id, slug, kind, status,
                          created_at, downloaded_at, download_count
                        ) VALUES (?, ?, ?, ?, 'downloaded', ?, ?, ?)
                        """,
                        (
                            f"dl-{uuid.uuid4().hex}",
                            uid,
                            slug,
                            kind,
                            now,
                            now,
                            count,
                        ),
                    )
                db.commit()
            finally:
                db.close()
        return count

    def get_download(self, user_id: str = "", slug: str = "microgreens") -> dict[str, Any] | None:
        with self._lock:
            db = self._connect()
            try:
                slug = slug or "microgreens"
                uid = self._canonical_uid(db, user_id)
                return self._find_download(db, uid, slug)
            finally:
                db.close()

    def save_payment(self, payment_id: str, user_id: str, slug: str) -> None:
        slug = slug or "microgreens"
        owner = self.find_user(user_id=user_id)
        uid = str(int(owner["user_id"])) if owner else str(user_id or "")
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                existing = self._find_download(db, uid, slug)
                reuse_id = str((existing or {}).get("payment_id") or "")
                if existing and not self._is_yookassa_id(reuse_id):
                    db.execute(
                        """
                        UPDATE downloads
                        SET payment_id = ?, user_id = ?, slug = ?, status = 'pending'
                        WHERE payment_id = ?
                        """,
                        (payment_id, uid, slug, reuse_id),
                    )
                elif db.kind == "mysql":
                    db.execute(
                        """
                        INSERT INTO downloads (payment_id, user_id, slug, status, created_at)
                        VALUES (?, ?, ?, 'pending', ?)
                        ON DUPLICATE KEY UPDATE
                          user_id = VALUES(user_id),
                          slug = VALUES(slug)
                        """,
                        (payment_id, uid, slug, now),
                    )
                else:
                    db.execute(
                        """
                        INSERT INTO downloads (payment_id, user_id, slug, status, created_at)
                        VALUES (?, ?, ?, 'pending', ?)
                        ON CONFLICT(payment_id) DO UPDATE SET
                          user_id = excluded.user_id,
                          slug = excluded.slug
                        """,
                        (payment_id, uid, slug, now),
                    )
                db.commit()
            finally:
                db.close()

    def get_payment(self, payment_id: str) -> dict[str, Any] | None:
        with self._lock:
            db = self._connect()
            try:
                return _row_dict(
                    db.execute(
                        f"SELECT {DOWNLOAD_SELECT} FROM downloads WHERE payment_id = ?",
                        (payment_id,),
                    ).fetchone()
                )
            finally:
                db.close()

    def pending_for_user(self, user_id: str) -> list[dict[str, Any]]:
        if not user_id:
            return []
        owner = self.find_user(user_id=user_id)
        uid = str(int(owner["user_id"])) if owner else str(user_id)
        ttl_seconds = pending_payment_ttl_seconds()
        now = _now()
        with self._lock:
            db = self._connect()
            try:
                rows = db.execute(
                    f"""
                    SELECT {DOWNLOAD_SELECT}
                    FROM downloads
                    WHERE user_id = ? AND status = 'pending'
                    ORDER BY created_at DESC
                    """,
                    (uid,),
                ).fetchall()
                pending = []
                for row in rows:
                    data = _row_dict(row) or {}
                    created_raw = data.get("created_at")
                    created = parse_iso(str(created_raw)) if created_raw else None
                    if created is None:
                        # Keep unknown timestamps as pending (safe fallback).
                        pending.append(data)
                        continue
                    age_seconds = (now - created).total_seconds()
                    if age_seconds <= ttl_seconds:
                        pending.append(data)
                return pending
            finally:
                db.close()

    def mark_payment(self, payment_id: str, status: str) -> None:
        if not payment_id:
            return
        with self._lock:
            db = self._connect()
            try:
                db.execute(
                    "UPDATE downloads SET status = ? WHERE payment_id = ?",
                    (status, payment_id),
                )
                db.commit()
            finally:
                db.close()

    def grant(
        self,
        email: str,
        user_id: str,
        slug: str,
        payment_id: str,
    ) -> dict[str, Any]:
        owner = self.ensure_user(user_id=user_id, email=email)
        uid = str(int(owner["user_id"])) if owner else str(user_id or "")
        existing = self.find(user_id=uid, slug=slug)
        if existing:
            if payment_id:
                self.mark_payment(payment_id, "succeeded")
            return existing
        with self._lock:
            db = self._connect()
            try:
                row = self._latest(db, uid, slug or "microgreens")
                if is_active(row):
                    self._mark_download_succeeded(
                        db,
                        payment_id=payment_id,
                        user_id=uid,
                        slug=slug or "microgreens",
                    )
                    db.commit()
                    return row or {}
                purchased_at = _now_iso()
                code = self._new_code(db)
                db.execute(
                    """
                    INSERT INTO access_codes
                      (code, purchased_at, expires_at, activated_at, slug, user_id, payment_id)
                    VALUES (?, ?, NULL, NULL, ?, ?, ?)
                    """,
                    (
                        code,
                        purchased_at,
                        slug or "microgreens",
                        uid,
                        payment_id or None,
                    ),
                )
                self._mark_download_succeeded(
                    db,
                    payment_id=payment_id,
                    user_id=uid,
                    slug=slug or "microgreens",
                )
                db.commit()
                return {
                    "email": (owner or {}).get("email") or "",
                    "code": code,
                    "purchased_at": purchased_at,
                    "expires_at": None,
                    "activated_at": None,
                    "slug": slug or "microgreens",
                    "user_id": uid,
                    "payment_id": payment_id,
                }
            finally:
                db.close()

    def _find_download(self, db: DbConn, user_id: str, slug: str) -> dict[str, Any] | None:
        uid = self._canonical_uid(db, user_id) or str(user_id or "")
        if not uid:
            return None
        return _row_dict(
            db.execute(
                f"""
                SELECT {DOWNLOAD_SELECT}
                FROM downloads
                WHERE user_id = ? AND slug = ?
                ORDER BY created_at DESC LIMIT 1
                """,
                (uid, slug),
            ).fetchone()
        )

    def _is_yookassa_id(self, payment_id: str) -> bool:
        return bool(payment_id) and not str(payment_id).startswith("dl-")

    def _mark_download_succeeded(
        self,
        db: DbConn,
        payment_id: str,
        user_id: str,
        slug: str,
    ) -> None:
        """Mark payment funnel row paid. Access dates stay on access_codes only."""
        if not payment_id:
            return
        now = _now_iso()
        uid = self._canonical_uid(db, user_id) or str(user_id or "")
        cur = db.execute(
            """
            UPDATE downloads
            SET status = 'succeeded',
                user_id = CASE WHEN user_id IS NULL OR user_id = '' THEN ? ELSE user_id END
            WHERE payment_id = ?
            """,
            (uid, payment_id),
        )
        if cur.rowcount:
            return
        row = self._find_download(db, uid, slug)
        if row:
            db.execute(
                """
                UPDATE downloads
                SET payment_id = CASE WHEN payment_id LIKE 'dl-%' THEN ? ELSE payment_id END,
                    status = 'succeeded'
                WHERE payment_id = ?
                """,
                (payment_id, row["payment_id"]),
            )
            return
        db.execute(
            """
            INSERT INTO downloads (
              payment_id, user_id, slug, kind, status,
              created_at, downloaded_at, download_count
            ) VALUES (?, ?, ?, NULL, 'succeeded', ?, NULL, 0)
            """,
            (payment_id, uid, slug, now),
        )

    def has_terms(self, user_id: str = "") -> bool:
        owner = self.find_user(user_id=user_id)
        uid = str(int(owner["user_id"])) if owner else str(user_id or "").strip()
        if not uid:
            return False
        with self._lock:
            db = self._connect()
            try:
                row = db.execute(
                    """
                    SELECT terms_version FROM user_terms
                    WHERE user_id = ?
                    ORDER BY accepted_at DESC LIMIT 1
                    """,
                    (uid,),
                ).fetchone()
            finally:
                db.close()
        if not row:
            return False
        version = row["terms_version"] if isinstance(row, dict) else row[0]
        return str(version or "") == TERMS_VERSION

    def accept_terms(self, user_id: str) -> bool:
        owner = self.find_user(user_id=user_id) or self.ensure_user(user_id=user_id)
        if not owner:
            return False
        uid = str(int(owner["user_id"]))
        key = f"user:{uid}"
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                if db.kind == "mysql":
                    db.execute(
                        """
                        INSERT INTO user_terms (consent_key, user_id, accepted_at, terms_version)
                        VALUES (?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                          user_id = VALUES(user_id),
                          accepted_at = VALUES(accepted_at),
                          terms_version = VALUES(terms_version)
                        """,
                        (key, uid, now, TERMS_VERSION),
                    )
                else:
                    db.execute(
                        """
                        INSERT INTO user_terms (consent_key, user_id, accepted_at, terms_version)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(consent_key) DO UPDATE SET
                          user_id = excluded.user_id,
                          accepted_at = excluded.accepted_at,
                          terms_version = excluded.terms_version
                        """,
                        (key, uid, now, TERMS_VERSION),
                    )
                db.commit()
            finally:
                db.close()
        return True

    def _new_code(self, db: DbConn) -> str:
        for _ in range(40):
            code = f"{secrets.randbelow(1_000_000):06d}"
            taken = db.execute("SELECT 1 FROM access_codes WHERE code = ?", (code,)).fetchone()
            if not taken:
                return code
        raise RuntimeError("could not allocate access code")
