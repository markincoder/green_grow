"""Access codes and downloads (SQLite or MySQL)."""

from __future__ import annotations

import os
import secrets
import threading
import uuid
from calendar import monthrange
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from db import DbConn, connect, default_database_url, describe_url

ACCESS_SELECT = "email, code, purchased_at, expires_at, activated_at, slug, user_id, payment_id"
DOWNLOAD_SELECT = (
    "payment_id, user_id, email, slug, app_name, kind, status, created_at, "
    "downloaded_at, download_count"
)
APP_NAMES = {"microgreens": "Микрозелень"}
TERMS_VERSION = "1"

SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS access_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  purchased_at TEXT NOT NULL,
  expires_at TEXT,
  activated_at TEXT,
  slug TEXT NOT NULL DEFAULT 'microgreens',
  user_id TEXT,
  payment_id TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_access_email ON access_codes (email, slug);
CREATE INDEX IF NOT EXISTS idx_access_user ON access_codes (user_id, slug);

CREATE TABLE IF NOT EXISTS downloads (
  payment_id TEXT PRIMARY KEY,
  user_id TEXT,
  email TEXT,
  slug TEXT NOT NULL,
  app_name TEXT,
  kind TEXT,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  downloaded_at TEXT,
  download_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_dl_user ON downloads (user_id, slug);
CREATE INDEX IF NOT EXISTS idx_dl_email ON downloads (email, slug);

CREATE TABLE IF NOT EXISTS user_terms (
  consent_key TEXT PRIMARY KEY,
  email TEXT,
  user_id TEXT,
  accepted_at TEXT NOT NULL,
  terms_version TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_terms_email ON user_terms (email);
CREATE INDEX IF NOT EXISTS idx_terms_user ON user_terms (user_id);
"""

MYSQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS access_codes (
  id INTEGER PRIMARY KEY AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL,
  code VARCHAR(16) NOT NULL,
  purchased_at VARCHAR(64) NOT NULL,
  expires_at VARCHAR(64),
  activated_at VARCHAR(64),
  slug VARCHAR(64) NOT NULL DEFAULT 'microgreens',
  user_id VARCHAR(255),
  payment_id VARCHAR(255),
  UNIQUE KEY uq_access_code (code),
  UNIQUE KEY uq_access_payment (payment_id),
  KEY idx_access_email (email, slug),
  KEY idx_access_user (user_id, slug)
);

CREATE TABLE IF NOT EXISTS downloads (
  payment_id VARCHAR(255) PRIMARY KEY,
  user_id VARCHAR(255),
  email VARCHAR(255),
  slug VARCHAR(64) NOT NULL,
  app_name VARCHAR(255),
  kind VARCHAR(16),
  status VARCHAR(32) NOT NULL,
  created_at VARCHAR(64) NOT NULL,
  downloaded_at VARCHAR(64),
  download_count INTEGER NOT NULL DEFAULT 0,
  KEY idx_dl_user (user_id, slug),
  KEY idx_dl_email (email, slug)
);

CREATE TABLE IF NOT EXISTS user_terms (
  consent_key VARCHAR(255) PRIMARY KEY,
  email VARCHAR(255),
  user_id VARCHAR(255),
  accepted_at VARCHAR(64) NOT NULL,
  terms_version VARCHAR(32) NOT NULL,
  KEY idx_terms_email (email),
  KEY idx_terms_user (user_id)
);
"""


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def _now_iso() -> str:
    return _now().isoformat()


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


def app_name_for(slug: str) -> str:
    key = (slug or "microgreens").strip() or "microgreens"
    return APP_NAMES.get(key, key)


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
    return data


def download_count_of(row: dict[str, Any] | None) -> int:
    if not row:
        return 0
    try:
        return max(0, int(row.get("download_count") or 0))
    except (TypeError, ValueError):
        return 0


class AccessDB:
    def __init__(self, url: str | Path | None = None) -> None:
        if isinstance(url, Path):
            url = f"sqlite:///{url.resolve().as_posix()}"
        self.url = (str(url).strip() if url else "") or default_database_url()
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
            self._ensure_download_columns(db, col_type)
            if db.kind == "mysql":
                self._ensure_mysql_indexes(db)
            db.commit()

    def _connect(self) -> DbConn:
        return connect(self.url)

    def _ensure_mysql_indexes(self, db: DbConn) -> None:
        # CREATE INDEX IF NOT EXISTS is not supported on older MySQL.
        for sql in (
            "CREATE INDEX idx_access_email ON access_codes (email, slug)",
            "CREATE INDEX idx_access_user ON access_codes (user_id, slug)",
            "CREATE INDEX idx_dl_user ON downloads (user_id, slug)",
            "CREATE INDEX idx_dl_email ON downloads (email, slug)",
            "CREATE INDEX idx_terms_email ON user_terms (email)",
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
            "app_name": "VARCHAR(255)" if db.kind == "mysql" else "TEXT",
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
                try:
                    db.execute(f"ALTER TABLE downloads DROP COLUMN {obsolete}")
                except Exception as exc:
                    print(f"downloads drop {obsolete}: {exc}", flush=True)

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

    def _latest(self, db: DbConn, user_id: str, email: str, slug: str) -> dict[str, Any] | None:
        if user_id:
            row = _row_dict(
                db.execute(
                    f"""
                    SELECT {ACCESS_SELECT}
                    FROM access_codes
                    WHERE user_id = ? AND slug = ?
                    ORDER BY id DESC LIMIT 1
                    """,
                    (user_id, slug),
                ).fetchone()
            )
            if row:
                return row
        if email:
            return _row_dict(
                db.execute(
                    f"""
                    SELECT {ACCESS_SELECT}
                    FROM access_codes
                    WHERE lower(email) = lower(?) AND slug = ?
                    ORDER BY id DESC LIMIT 1
                    """,
                    (email.strip(), slug),
                ).fetchone()
            )
        return None

    def find(self, user_id: str = "", email: str = "", slug: str = "microgreens") -> dict[str, Any] | None:
        slug = slug or "microgreens"
        with self._lock:
            db = self._connect()
            try:
                row = self._latest(db, user_id, email, slug)
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
        self, code: str, email: str, slug: str = "microgreens"
    ) -> tuple[str | None, dict[str, Any] | None]:
        digits = "".join(ch for ch in (code or "") if ch.isdigit())
        mail = (email or "").strip()
        if len(digits) != 6 or "@" not in mail:
            return "invalid", None
        row = self.lookup_code(digits, slug)
        if not row:
            return "invalid", None
        stored = str(row.get("email") or "").strip()
        if stored.lower() != mail.lower():
            return "mismatch", None
        if row.get("activated_at") and not is_active(row):
            return "expired", None
        if not is_active(row):
            return "expired", None
        # Already activated — keep first activation dates, do not renew.
        if row.get("activated_at"):
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
                cur = db.execute(
                    """
                    UPDATE access_codes
                    SET activated_at = ?, expires_at = ?
                    WHERE code = ? AND slug = ? AND activated_at IS NULL
                    """,
                    (activated_at, expires_at, digits, slug or "microgreens"),
                )
                # Another request may have activated first — reload stored dates.
                if not cur.rowcount:
                    fresh = _row_dict(
                        db.execute(
                            f"""
                            SELECT {ACCESS_SELECT}
                            FROM access_codes
                            WHERE code = ? AND slug = ?
                            ORDER BY id DESC LIMIT 1
                            """,
                            (digits, slug or "microgreens"),
                        ).fetchone()
                    )
                    db.commit()
                    if fresh and fresh.get("activated_at"):
                        if not fresh.get("expires_at"):
                            fresh["expires_at"] = expires_iso(str(fresh.get("activated_at")))
                        return None, fresh
                db.commit()
            finally:
                db.close()
        row["activated_at"] = activated_at
        row["expires_at"] = expires_at
        return None, row

    def record_download(
        self,
        user_id: str,
        email: str,
        slug: str,
        kind: str,
    ) -> int:
        slug = slug or "microgreens"
        kind = "apk" if str(kind).lower() == "apk" else "pwa"
        mail = (email or "").strip()
        uid = user_id or ""
        if not mail and not uid:
            return 0
        now = _now_iso()
        name = app_name_for(slug)
        with self._lock:
            db = self._connect()
            try:
                row = self._find_download_by_email(db, mail, slug) or self._find_download(
                    db, uid, mail, slug
                )
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
                        SET email = CASE WHEN email IS NULL OR email = '' THEN ? ELSE email END,
                            user_id = CASE WHEN user_id IS NULL OR user_id = '' THEN ? ELSE user_id END,
                            app_name = COALESCE(NULLIF(app_name, ''), ?),
                            kind = ?,
                            downloaded_at = ?,
                            download_count = ?
                        WHERE payment_id = ?
                        """,
                        (mail, uid, name, kind, now, count, row["payment_id"]),
                    )
                else:
                    count = 1
                    db.execute(
                        """
                        INSERT INTO downloads (
                          payment_id, user_id, email, slug, app_name, kind, status,
                          created_at, downloaded_at, download_count
                        ) VALUES (?, ?, ?, ?, ?, ?, 'downloaded', ?, ?, ?)
                        """,
                        (
                            f"dl-{uuid.uuid4().hex}",
                            uid,
                            mail,
                            slug,
                            name,
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

    def get_download(self, user_id: str = "", email: str = "", slug: str = "microgreens") -> dict[str, Any] | None:
        with self._lock:
            db = self._connect()
            try:
                slug = slug or "microgreens"
                return self._find_download_by_email(db, email, slug) or self._find_download(
                    db, user_id, email, slug
                )
            finally:
                db.close()

    def save_payment(self, payment_id: str, user_id: str, email: str, slug: str) -> None:
        slug = slug or "microgreens"
        uid = user_id or ""
        mail = email or ""
        name = app_name_for(slug)
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                existing = self._find_download(db, uid, mail, slug)
                reuse_id = str((existing or {}).get("payment_id") or "")
                if existing and not self._is_yookassa_id(reuse_id):
                    db.execute(
                        """
                        UPDATE downloads
                        SET payment_id = ?, user_id = ?, email = ?, slug = ?, app_name = ?, status = 'pending'
                        WHERE payment_id = ?
                        """,
                        (payment_id, uid, mail, slug, name, reuse_id),
                    )
                elif db.kind == "mysql":
                    db.execute(
                        """
                        INSERT INTO downloads (payment_id, user_id, email, slug, app_name, status, created_at)
                        VALUES (?, ?, ?, ?, ?, 'pending', ?)
                        ON DUPLICATE KEY UPDATE
                          user_id = VALUES(user_id),
                          email = VALUES(email),
                          slug = VALUES(slug),
                          app_name = VALUES(app_name)
                        """,
                        (payment_id, uid, mail, slug, name, now),
                    )
                else:
                    db.execute(
                        """
                        INSERT INTO downloads (payment_id, user_id, email, slug, app_name, status, created_at)
                        VALUES (?, ?, ?, ?, ?, 'pending', ?)
                        ON CONFLICT(payment_id) DO UPDATE SET
                          user_id = excluded.user_id,
                          email = excluded.email,
                          slug = excluded.slug,
                          app_name = excluded.app_name
                        """,
                        (payment_id, uid, mail, slug, name, now),
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
                    (user_id,),
                ).fetchall()
                return [_row_dict(row) or {} for row in rows]
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
        existing = self.find(user_id=user_id, email=email, slug=slug)
        if existing:
            if payment_id:
                self.mark_payment(payment_id, "succeeded")
            return existing
        with self._lock:
            db = self._connect()
            try:
                row = self._latest(db, user_id, email, slug or "microgreens")
                if is_active(row):
                    self._mark_download_succeeded(
                        db,
                        payment_id=payment_id,
                        email=email,
                        user_id=user_id,
                        slug=slug or "microgreens",
                    )
                    db.commit()
                    return row or {}
                purchased_at = _now_iso()
                code = self._new_code(db)
                db.execute(
                    """
                    INSERT INTO access_codes
                      (email, code, purchased_at, expires_at, activated_at, slug, user_id, payment_id)
                    VALUES (?, ?, ?, NULL, NULL, ?, ?, ?)
                    """,
                    (
                        email.strip(),
                        code,
                        purchased_at,
                        slug or "microgreens",
                        user_id or "",
                        payment_id or None,
                    ),
                )
                self._mark_download_succeeded(
                    db,
                    payment_id=payment_id,
                    email=email.strip(),
                    user_id=user_id or "",
                    slug=slug or "microgreens",
                )
                db.commit()
                return {
                    "email": email.strip(),
                    "code": code,
                    "purchased_at": purchased_at,
                    "expires_at": None,
                    "activated_at": None,
                    "slug": slug or "microgreens",
                    "user_id": user_id or "",
                    "payment_id": payment_id,
                }
            finally:
                db.close()

    def _find_download_by_email(self, db: DbConn, email: str, slug: str) -> dict[str, Any] | None:
        mail = (email or "").strip()
        if not mail:
            return None
        return _row_dict(
            db.execute(
                f"""
                SELECT {DOWNLOAD_SELECT}
                FROM downloads
                WHERE lower(email) = lower(?) AND slug = ?
                ORDER BY created_at DESC LIMIT 1
                """,
                (mail, slug),
            ).fetchone()
        )

    def _find_download(self, db: DbConn, user_id: str, email: str, slug: str) -> dict[str, Any] | None:
        if user_id:
            row = _row_dict(
                db.execute(
                    f"""
                    SELECT {DOWNLOAD_SELECT}
                    FROM downloads
                    WHERE user_id = ? AND slug = ?
                    ORDER BY created_at DESC LIMIT 1
                    """,
                    (user_id, slug),
                ).fetchone()
            )
            if row:
                return row
        if email:
            return _row_dict(
                db.execute(
                    f"""
                    SELECT {DOWNLOAD_SELECT}
                    FROM downloads
                    WHERE lower(email) = lower(?) AND slug = ?
                    ORDER BY created_at DESC LIMIT 1
                    """,
                    (email.strip(), slug),
                ).fetchone()
            )
        return None

    def _is_yookassa_id(self, payment_id: str) -> bool:
        return bool(payment_id) and not str(payment_id).startswith("dl-")

    def _mark_download_succeeded(
        self,
        db: DbConn,
        payment_id: str,
        email: str,
        user_id: str,
        slug: str,
    ) -> None:
        """Mark payment funnel row paid. Access dates stay on access_codes only."""
        if not payment_id:
            return
        name = app_name_for(slug)
        now = _now_iso()
        cur = db.execute(
            """
            UPDATE downloads
            SET status = 'succeeded',
                app_name = COALESCE(NULLIF(app_name, ''), ?),
                email = CASE WHEN email IS NULL OR email = '' THEN ? ELSE email END,
                user_id = CASE WHEN user_id IS NULL OR user_id = '' THEN ? ELSE user_id END
            WHERE payment_id = ?
            """,
            (name, email, user_id, payment_id),
        )
        if cur.rowcount:
            return
        row = self._find_download(db, user_id, email, slug)
        if row:
            db.execute(
                """
                UPDATE downloads
                SET payment_id = CASE WHEN payment_id LIKE 'dl-%' THEN ? ELSE payment_id END,
                    status = 'succeeded',
                    app_name = COALESCE(NULLIF(app_name, ''), ?)
                WHERE payment_id = ?
                """,
                (payment_id, name, row["payment_id"]),
            )
            return
        db.execute(
            """
            INSERT INTO downloads (
              payment_id, user_id, email, slug, app_name, kind, status,
              created_at, downloaded_at, download_count
            ) VALUES (?, ?, ?, ?, ?, NULL, 'succeeded', ?, NULL, 0)
            """,
            (payment_id, user_id or "", email, slug, name, now),
        )

    def _terms_key(self, user_id: str, email: str) -> str:
        mail = (email or "").strip().lower()
        if mail:
            return f"email:{mail}"
        uid = (user_id or "").strip()
        return f"user:{uid}" if uid else ""

    def has_terms(self, user_id: str = "", email: str = "") -> bool:
        mail = (email or "").strip()
        uid = (user_id or "").strip()
        if not mail and not uid:
            return False
        with self._lock:
            db = self._connect()
            try:
                row = None
                if mail:
                    row = db.execute(
                        """
                        SELECT terms_version FROM user_terms
                        WHERE lower(email) = lower(?)
                        ORDER BY accepted_at DESC LIMIT 1
                        """,
                        (mail,),
                    ).fetchone()
                if row is None and uid:
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

    def accept_terms(self, user_id: str, email: str) -> bool:
        mail = (email or "").strip()
        uid = (user_id or "").strip()
        key = self._terms_key(uid, mail)
        if not key:
            return False
        now = _now_iso()
        with self._lock:
            db = self._connect()
            try:
                if db.kind == "mysql":
                    db.execute(
                        """
                        INSERT INTO user_terms (consent_key, email, user_id, accepted_at, terms_version)
                        VALUES (?, ?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                          email = VALUES(email),
                          user_id = VALUES(user_id),
                          accepted_at = VALUES(accepted_at),
                          terms_version = VALUES(terms_version)
                        """,
                        (key, mail, uid, now, TERMS_VERSION),
                    )
                else:
                    db.execute(
                        """
                        INSERT INTO user_terms (consent_key, email, user_id, accepted_at, terms_version)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(consent_key) DO UPDATE SET
                          email = excluded.email,
                          user_id = excluded.user_id,
                          accepted_at = excluded.accepted_at,
                          terms_version = excluded.terms_version
                        """,
                        (key, mail, uid, now, TERMS_VERSION),
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
