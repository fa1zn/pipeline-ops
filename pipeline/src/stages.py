"""The three stages. Each one is safe to run twice."""
import datetime as dt

from . import config
from .metrics import rows_processed, watermark_lag
from .db import watermark


def ingest(conn):
    """
    Copy new upstream rows into the immutable raw table.

    The window starts at the watermark minus a lookback rather than at the
    watermark, because upstream assigns `occurred_at` at event time and rows can
    land out of order. Starting at the watermark loses every row that arrives
    late. The lookback re-reads rows that are already present, which costs
    nothing because the insert is idempotent on the upstream id.
    """
    since = watermark(conn)
    if since is None:
        since = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    else:
        since -= dt.timedelta(seconds=config.LOOKBACK_SECONDS)

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO raw_events (upstream_id, occurred_at, source, payload)
            SELECT id, occurred_at, source, payload
              FROM upstream_events
             WHERE occurred_at >= %s
            ON CONFLICT (upstream_id) DO NOTHING
            """,
            (since,))
        inserted = cur.rowcount
    conn.commit()
    rows_processed.labels(stage="ingest").set(max(inserted, 0))
    return inserted


def transform(conn):
    """
    Rebuild the derived rows that do not have one yet.

    Derived rows are a pure function of raw rows, so this never needs upstream
    and can be re-run after a bad deploy by deleting from `derived_events`.
    """
    if config.FAULT == "transform_error":
        raise RuntimeError("injected fault: transform_error")

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO derived_events (upstream_id, occurred_at, source,
                                        token_count, normalised)
            SELECT r.upstream_id, r.occurred_at, r.source,
                   array_length(regexp_split_to_array(trim(r.payload), '\\s+'), 1),
                   lower(regexp_replace(r.payload, '\\s+', ' ', 'g'))
              FROM raw_events r
              LEFT JOIN derived_events d USING (upstream_id)
             WHERE d.upstream_id IS NULL
            ON CONFLICT (upstream_id) DO NOTHING
            """)
        built = cur.rowcount
    conn.commit()
    rows_processed.labels(stage="transform").set(max(built, 0))
    return built


def publish(conn):
    """
    Record how far behind the data is.

    This is deliberately separate from whether the run succeeded. A run can
    finish green every night while upstream has been dead for a week, and only
    this number notices.
    """
    if config.FAULT == "publish_slow":
        import time
        time.sleep(config.BUDGET_SECONDS["publish"] + 5)

    wm = watermark(conn)
    if wm is not None:
        lag = (dt.datetime.now(dt.timezone.utc) - wm).total_seconds()
        watermark_lag.set(max(lag, 0))
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM derived_events")
        total = cur.fetchone()[0]
    rows_processed.labels(stage="publish").set(total)
    return total
