"""Async database helper used by the test API."""

import asyncpg
import os
import re
from typing import Optional, Union

class PortalDB:
    """Simple async DB wrapper for PostgreSQL.

    This class requires the ``asyncpg`` package to be installed. It opens a
    PostgreSQL connection using credentials from environment variables or the
    defaults specified in ``tests/portalwebapi.pl``.

    You can increase the connection pool size by setting ``PORTAL_DB_POOL_SIZE``
    or passing ``max_connections`` to the constructor. This enables better
    concurrency for high traffic scenarios.
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

        self.pool = None

    async def connect(self):
        self.pool = await asyncpg.create_pool(
            user=os.getenv("PORTAL_DB_USER", "admin_db"),
            password=os.getenv("PORTAL_DB_PASS", "OnesNeser2!"),
            database=os.getenv("PORTAL_DB_NAME", "mainbase"),
            host=os.getenv("PORTAL_DB_HOST", "localhost"),
            port=int(os.getenv("PORTAL_DB_PORT", "5432")),
            min_size=1,
            max_size=int(os.getenv("PORTAL_DB_POOL_SIZE", "10")),
        )

    def _adapt_query(self, query: str) -> str:
        """Convert SQLite placeholders to Postgres style when needed."""
        # replace '?' placeholders with %s for psycopg2
        return re.sub(r"\?", "%s", query)

    async def execute(self, query: str, params: Optional[Union[tuple, list]] = None) -> int:
        params = params or ()

        async with self.pool.acquire() as conn:
            try:
                result = await conn.execute(query, *params)
                return result
            except Exception as e:
                await conn.execute("ROLLBACK")
                raise

    async def fetchone(self, query: str, params: Optional[Union[tuple, list]] = None):
        params = params or ()
        async with self.pool.acquire() as conn:
            try:
                row = await conn.fetchrow(query, *params)
                return dict(row) if row else None
            except Exception as e:
                await conn.execute("ROLLBACK")
                raise

    async def fetchall(self, query: str, params: Optional[Union[tuple, list]] = None):
        """Return a list of rows as dictionaries."""
        params = params or ()
        async with self.pool.acquire() as conn:
            try:
                rows = await conn.fetch(query, *params)
                return [dict(row) for row in rows]
            except Exception as e:
                await conn.execute("ROLLBACK")
                raise

    async def close(self) -> None:
        if self.pool:
            await self.pool.close()
