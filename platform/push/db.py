"""DATABASE_URL: sqlite locally, mysql+pymysql on prod."""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

DEFAULT_MYSQL_DB = "agronizer"


def default_database_url(data_dir: Path | None = None) -> str:
    url = (os.environ.get("DATABASE_URL") or "").strip()
    if url:
        return url
    root = Path(data_dir or os.environ.get("DATA_DIR") or Path(__file__).resolve().parent / "data")
    path = (root / "access.sqlite").resolve()
    return f"sqlite:///{path.as_posix()}"


def sqlite_path_from_url(url: str) -> Path:
    rest = url.split("?", 1)[0]
    if rest.startswith("sqlite:////"):
        rest = rest[len("sqlite:///"):]
    elif rest.startswith("sqlite:///"):
        rest = rest[len("sqlite:///"):]
    else:
        raise ValueError(f"Not a sqlite URL: {url}")
    path = Path(unquote(rest))
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    return path


def parse_mysql(url: str) -> dict[str, Any]:
    parsed = urlparse(url)
    database = (parsed.path or "").lstrip("/").split("/")[0]
    charset = (parse_qs(parsed.query).get("charset") or ["utf8mb4"])[0]
    return {
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "host": parsed.hostname or "127.0.0.1",
        "port": parsed.port or 3306,
        "database": database or DEFAULT_MYSQL_DB,
        "charset": charset,
    }


def describe_url(url: str) -> str:
    if url.startswith("sqlite:"):
        return f"sqlite {sqlite_path_from_url(url)}"
    cfg = parse_mysql(url)
    return f"mysql {cfg['user']}@{cfg['host']}:{cfg['port']}/{cfg['database']}"


class DbConn:
    def __init__(self, raw: Any, kind: str) -> None:
        self.raw = raw
        self.kind = kind

    def execute(self, sql: str, params: tuple[Any, ...] | list[Any] = ()):
        if self.kind == "mysql":
            sql = sql.replace("?", "%s")
        cur = self.raw.cursor()
        cur.execute(sql, params)
        return cur

    def executescript(self, script: str) -> None:
        for stmt in script.split(";"):
            stmt = stmt.strip()
            if stmt:
                self.execute(stmt)

    def commit(self) -> None:
        self.raw.commit()

    def close(self) -> None:
        self.raw.close()

    def __enter__(self) -> DbConn:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def connect(url: str | None = None) -> DbConn:
    url = (url or default_database_url()).strip()
    if url.startswith("sqlite:"):
        path = sqlite_path_from_url(url)
        path.parent.mkdir(parents=True, exist_ok=True)
        raw = sqlite3.connect(path, check_same_thread=False)
        raw.row_factory = sqlite3.Row
        raw.execute("PRAGMA journal_mode=WAL")
        raw.execute("PRAGMA foreign_keys=ON")
        return DbConn(raw, "sqlite")
    if url.startswith("mysql"):
        import pymysql
        from pymysql.cursors import DictCursor

        cfg = parse_mysql(url)
        bootstrap = pymysql.connect(
            host=cfg["host"],
            port=cfg["port"],
            user=cfg["user"],
            password=cfg["password"],
            charset=cfg["charset"],
            autocommit=True,
        )
        try:
            with bootstrap.cursor() as cur:
                cur.execute(
                    f"CREATE DATABASE IF NOT EXISTS `{cfg['database']}` "
                    "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
                )
        finally:
            bootstrap.close()
        raw = pymysql.connect(
            host=cfg["host"],
            port=cfg["port"],
            user=cfg["user"],
            password=cfg["password"],
            database=cfg["database"],
            charset=cfg["charset"],
            cursorclass=DictCursor,
            autocommit=False,
        )
        return DbConn(raw, "mysql")
    raise ValueError(f"Unsupported DATABASE_URL scheme: {url.split(':', 1)[0]}")
