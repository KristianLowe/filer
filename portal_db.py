"""Async database helper used by the test API."""

import sqlite3
import asyncio
import os
import re
from typing import Optional, Union

try:  # Optional Postgres support when psycopg2 is available
    import psycopg2  # type: ignore
    import psycopg2.extras  # type: ignore
    from psycopg2 import pool as pg_pool  # type: ignore
except Exception:  # pragma: no cover - fallback when package missing
    psycopg2 = None

class PortalDB:
    """Simple async DB wrapper for SQLite or PostgreSQL.

    When the ``psycopg2`` package is installed, the class will attempt to open
    a PostgreSQL connection using credentials from environment variables or the
    defaults specified in ``tests/portalwebapi.pl``. Otherwise an in-memory
    SQLite database is used. This keeps the test suite self contained while
    allowing the same code to run against Postgres in the real environment.

    When running against PostgreSQL you can increase the connection pool size by
    setting ``PORTAL_DB_POOL_SIZE`` or passing ``max_connections`` to the
    constructor. This enables better concurrency for high traffic scenarios.
    """

    def __init__(
        self,
        dsn: Optional[str] = None,
        *,
        user: Optional[str] = None,
        password: Optional[str] = None,
        max_connections: Optional[int] = None,
    ) -> None:
        # Default connection details mirror the Perl script
        dsn = dsn or os.getenv("PORTAL_DB_DSN", "dbi:Pg:dbname=mainbase;host=localhost;port=5432")
        user = user or os.getenv("PORTAL_DB_USER", "admin_db")
        password = password or os.getenv("PORTAL_DB_PASS", "OnesNeser2!")

        use_sqlite = dsn == ":memory:" or psycopg2 is None
        self.pool = None

        if use_sqlite:
            self.driver = "sqlite"
            self.conn = sqlite3.connect(":memory:", check_same_thread=False)
            self.conn.row_factory = sqlite3.Row
        else:
            self.driver = "postgres"
            if dsn.startswith("dbi:Pg:"):
                dsn = dsn[len("dbi:Pg:"):].replace(";", " ")
            max_connections = max_connections or int(os.getenv("PORTAL_DB_POOL_SIZE", "1"))
            if max_connections > 1 and psycopg2 is not None:
                self.pool = pg_pool.SimpleConnectionPool(
                    1,
                    max_connections,
                    dsn=dsn,
                    user=user,
                    password=password,
                    cursor_factory=psycopg2.extras.RealDictCursor,
                )
                self.conn = None
            else:
                self.conn = psycopg2.connect(
                    dsn=dsn,
                    user=user,
                    password=password,
                    cursor_factory=psycopg2.extras.RealDictCursor,
                )

    def _adapt_query(self, query: str) -> str:
        """Convert SQLite placeholders to Postgres style when needed."""
        if self.driver == "postgres":
            # replace '?' placeholders with %s for psycopg2
            return re.sub(r"\?", "%s", query)
        return query

    async def execute(self, query: str, params: Optional[Union[tuple, list]] = None) -> int:
        params = params or ()

        def run():
            if self.driver == "sqlite":
                cur = self.conn.execute(query, params)
                self.conn.commit()
                return cur.rowcount
            else:
                conn = self.pool.getconn() if self.pool else self.conn
                try:
                    cur = conn.cursor()
                    cur.execute(self._adapt_query(query), params)
                    conn.commit()
                    rowcount = cur.rowcount
                    cur.close()
                    return rowcount
                finally:
                    if self.pool:
                        self.pool.putconn(conn)

        return await asyncio.to_thread(run)

    async def fetchone(self, query: str, params: Optional[Union[tuple, list]] = None):
        params = params or ()
        def run():
            if self.driver == "sqlite":
                cur = self.conn.execute(query, params)
                row = cur.fetchone()
                return dict(row) if row else None
            else:
                conn = self.pool.getconn() if self.pool else self.conn
                try:
                    cur = conn.cursor()
                    cur.execute(self._adapt_query(query), params)
                    row = cur.fetchone()
                    cur.close()
                    return row
                finally:
                    if self.pool:
                        self.pool.putconn(conn)
        return await asyncio.to_thread(run)

    async def fetchall(self, query: str, params: Optional[Union[tuple, list]] = None):
        """Return a list of rows as dictionaries."""
        params = params or ()
        def run():
            if self.driver == "sqlite":
                cur = self.conn.execute(query, params)
                rows = cur.fetchall()
                return [dict(row) for row in rows]
            else:
                conn = self.pool.getconn() if self.pool else self.conn
                try:
                    cur = conn.cursor()
                    cur.execute(self._adapt_query(query), params)
                    rows = cur.fetchall()
                    cur.close()
                    return rows
                finally:
                    if self.pool:
                        self.pool.putconn(conn)
        return await asyncio.to_thread(run)

    async def close(self) -> None:
        def run():
            if self.pool:
                self.pool.closeall()
            elif self.conn:
                self.conn.close()

        await asyncio.to_thread(run)
