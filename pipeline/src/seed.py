"""
Stand in for whatever upstream would be. Writes events with a spread of
`occurred_at` values, some of them backdated, so the lookback has something to
catch and the pipeline is exercised the way a real one is.
"""
import datetime as dt
import random
import sys

from .db import connect, ensure_schema

WORDS = "invoice shipment claim quote renewal endorsement binder policy audit".split()


def seed(n=400, late_fraction=0.08):
    conn = connect()
    ensure_schema(conn)
    now = dt.datetime.now(dt.timezone.utc)
    late = 0
    with conn.cursor() as cur:
        for _ in range(n):
            if random.random() < late_fraction:
                when = now - dt.timedelta(seconds=random.randint(60, 800))
                late += 1
            else:
                when = now - dt.timedelta(seconds=random.randint(0, 45))
            cur.execute(
                "INSERT INTO upstream_events (occurred_at, source, payload)"
                " VALUES (%s, %s, %s)",
                (when, random.choice(["portal", "email", "api"]),
                 "  ".join(random.choices(WORDS, k=random.randint(4, 14)))))
    conn.commit()
    conn.close()
    print(f"seeded {n} upstream events, {late} of them backdated", flush=True)


if __name__ == "__main__":
    seed(int(sys.argv[1]) if len(sys.argv) > 1 else 400)
