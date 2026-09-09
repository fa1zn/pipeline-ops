import os

DSN = os.environ.get("PIPELINE_DSN", "postgresql://pipeline:pipeline@postgres:5432/pipeline")
PUSHGATEWAY = os.environ.get("PUSHGATEWAY", "pushgateway:9091")
JOB = os.environ.get("PIPELINE_JOB", "nightly")

# How far back to re-read on every run. Upstream rows can land with a timestamp
# earlier than rows already ingested, so a watermark alone drops them. The
# lookback is the cost of not needing upstream to be ordered.
LOOKBACK_SECONDS = int(os.environ.get("LOOKBACK_SECONDS", 900))

# Per-stage wall clock budgets. Exceeding one is a warning, not a failure: the
# run still produced correct output, it just took longer than it should.
BUDGET_SECONDS = {"ingest": 30.0, "transform": 20.0, "publish": 10.0}

# Injected by the incident drills. Never set in normal operation.
FAULT = os.environ.get("PIPELINE_FAULT", "")
