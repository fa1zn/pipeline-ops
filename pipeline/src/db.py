"""
Schema and the two properties that let a run be repeated safely.

`raw` is immutable and keyed on the upstream id, so re-reading a window that was
already ingested inserts nothing. `derived` is rebuilt from `raw`, so it can be
dropped and recomputed without asking upstream for anything.
"""
import psycopg

from . import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS upstream_events (
    id           BIGSERIAL PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL,
    source       TEXT        NOT NULL,
    payload      TEXT        NOT NULL
);
CREATE INDEX IF NOT EXISTS upstream_events_occurred_at
    ON upstream_events (occurred_at);

CREATE TABLE IF NOT EXISTS raw_events (
    upstream_id  BIGINT      PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL,
    source       TEXT        NOT NULL,
    payload      TEXT        NOT NULL,
    ingested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS raw_events_occurred_at ON raw_events (occurred_at);

CREATE TABLE IF NOT EXISTS derived_events (
    upstream_id  BIGINT      PRIMARY KEY REFERENCES raw_events (upstream_id),
    occurred_at  TIMESTAMPTZ NOT NULL,
    source       TEXT        NOT NULL,
    token_count  INT         NOT NULL,
    normalised   TEXT        NOT NULL
);

CREATE TABLE IF NOT EXISTS run_log (
    run_id      BIGSERIAL PRIMARY KEY,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    status      TEXT NOT NULL,
    failed_stage TEXT,
    detail      TEXT
);
"""


def connect():
    return psycopg.connect(config.DSN, autocommit=False)


def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute(SCHEMA)
    conn.commit()


def watermark(conn):
    """Newest row already ingested. None on an empty table."""
    with conn.cursor() as cur:
        cur.execute("SELECT max(occurred_at) FROM raw_events")
        return cur.fetchone()[0]
