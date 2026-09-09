"""
Run every stage in order, then report.

Exit code matters as much as the metrics: the scheduler records a non-zero exit,
so a run that dies before it can push anything is still visible somewhere. The
metrics path is not allowed to be the only way a failure is noticed.
"""
import sys
import time
import traceback

from . import config, metrics
from .db import connect, ensure_schema
from .stages import ingest, transform, publish

STAGES = [("ingest", ingest), ("transform", transform), ("publish", publish)]


def main():
    started = time.monotonic()
    metrics.init_stages([n for n, _ in STAGES])
    conn = connect()
    ensure_schema(conn)

    with conn.cursor() as cur:
        cur.execute("INSERT INTO run_log (status) VALUES ('running') RETURNING run_id")
        run_id = cur.fetchone()[0]
    conn.commit()

    failed_stage = detail = None
    pushed_success = False
    try:
        for name, fn in STAGES:
            with metrics.timed(name):
                count = fn(conn)
            print(f"{name}: {count}", flush=True)
        metrics.last_success.set(time.time())
        metrics.run_failed.set(0)
        status = "ok"
        pushed_success = True
    except Exception as exc:
        conn.rollback()
        failed_stage = name
        detail = f"{type(exc).__name__}: {exc}"
        status = "failed"
        metrics.run_failed.set(1)
        traceback.print_exc()
    finally:
        metrics.run_duration.set(time.monotonic() - started)
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE run_log SET finished_at = now(), status = %s,"
                " failed_stage = %s, detail = %s WHERE run_id = %s",
                (status, failed_stage, detail, run_id))
        conn.commit()
        try:
            metrics.push()
            if pushed_success:
                metrics.push_success()
        except Exception as exc:                       # noqa: BLE001
            # A dead gateway must not turn a good run into a failed one, but it
            # must be loud, because from here on the dashboards are lying.
            print(f"metrics push failed: {exc}", file=sys.stderr, flush=True)
        conn.close()

    print(f"run {run_id} {status} in {time.monotonic() - started:.1f}s", flush=True)
    return 0 if status == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
