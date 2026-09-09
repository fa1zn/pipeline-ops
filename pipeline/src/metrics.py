"""
The metric contract for a batch job.

Prometheus pulls. A job that runs for ninety seconds and exits is almost never
up when the scrape lands, so it cannot be scraped directly. Pushgateway exists
for exactly this case: the job pushes on the way out and Prometheus scrapes the
gateway instead.

Two consequences follow, and both of them decide what is allowed in this file.

First, everything here is a Gauge. A Counter is wrong through a pushgateway: the
process starts a fresh registry at zero on every run, and the push replaces the
whole group rather than adding to it, so the series never climbs and rate() and
increase() both return zero no matter how many times the job ran. The first
version of this file used Counters, and two successful runs produced
`increase(pipeline_run_total[5m]) == 0`. Gauges describing the last run are the
honest shape: "this run moved 400 rows", not "400 rows have ever moved".

Second, Pushgateway never expires what it holds. A job that stops running leaves
its last successful push sitting there forever, so a dashboard built on run
counts stays green through a total outage. That is why the load-bearing metric
is a timestamp: a stopped job makes it go stale, and staleness is a thing an
alert can see.

Labels are bounded on purpose. `stage` takes three values, and nothing is
labelled with a run id, which would add a series per run and never stop.
"""
import time
from contextlib import contextmanager

from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

from . import config

# Two registries, pushed under two grouping keys, because they have different
# lifetimes. Everything about the current run belongs in `registry` and is
# replaced wholesale each time. The liveness timestamp must survive a failed
# run: a push replaces the whole group, so a failure that pushed a
# default-zero `last_success` would erase the real one and the dashboard would
# read "since last successful run: 56.7 years". Separate group, only written
# on success, never zeroed.
registry = CollectorRegistry()
liveness = CollectorRegistry()

# --- liveness ---------------------------------------------------------------
# Goes stale when the job stops running at all, which is the outage no failure
# signal can see, because a job that never starts never fails.
last_success = Gauge(
    "pipeline_last_success_timestamp_seconds",
    "Unix time of the last run where every stage succeeded", registry=liveness)

# --- data freshness ---------------------------------------------------------
# A different question from liveness. The job can succeed on schedule all week
# while upstream is dead, and only this number notices.
watermark_lag = Gauge(
    "pipeline_watermark_lag_seconds",
    "Age of the newest row the pipeline has ingested", registry=registry)

# --- this run ---------------------------------------------------------------
stage_success = Gauge(
    "pipeline_stage_success", "1 if the stage completed in the last run, 0 if it raised",
    ["stage"], registry=registry)

# Separates "ran and failed" from "never got the chance". Without it, a fault in
# `transform` pages once for transform and once for every stage behind it, because
# a stage that never executed and a stage that raised both sit at success=0. One
# root cause, three pages, and the real one is not obviously the real one.
stage_ran = Gauge(
    "pipeline_stage_ran", "1 if the stage was attempted in the last run",
    ["stage"], registry=registry)

stage_duration = Gauge(
    "pipeline_stage_duration_seconds", "Wall clock of the stage in the last run",
    ["stage"], registry=registry)

rows_processed = Gauge(
    "pipeline_rows_processed", "Rows the stage handled in the last run",
    ["stage"], registry=registry)

stage_over_budget = Gauge(
    "pipeline_stage_over_budget", "1 if the stage exceeded its time budget in the last run",
    ["stage"], registry=registry)

run_duration = Gauge(
    "pipeline_run_duration_seconds", "Wall clock of the last full run", registry=registry)

run_failed = Gauge(
    "pipeline_run_failed", "1 if the last run did not finish every stage", registry=registry)


def init_stages(stages):
    """
    Publish a zero for every stage before anything runs.

    Without this, a run that dies in `ingest` never touches `transform`, the
    series is simply absent, and an alert written as `== 0` has nothing to match.
    Absent and healthy look identical to a query, which is how a broken stage
    hides.
    """
    for s in stages:
        stage_success.labels(stage=s).set(0)
        stage_ran.labels(stage=s).set(0)
        stage_duration.labels(stage=s).set(0)
        rows_processed.labels(stage=s).set(0)
        stage_over_budget.labels(stage=s).set(0)


@contextmanager
def timed(stage):
    stage_ran.labels(stage=stage).set(1)
    started = time.monotonic()
    try:
        yield
    except Exception:
        stage_success.labels(stage=stage).set(0)
        stage_duration.labels(stage=stage).set(time.monotonic() - started)
        raise
    else:
        elapsed = time.monotonic() - started
        stage_success.labels(stage=stage).set(1)
        stage_duration.labels(stage=stage).set(elapsed)
        budget = config.BUDGET_SECONDS.get(stage)
        stage_over_budget.labels(stage=stage).set(1 if budget and elapsed > budget else 0)


def push():
    """Per-run metrics. Replaces the previous run's group, which is the point."""
    push_to_gateway(config.PUSHGATEWAY, job=config.JOB,
                    grouping_key={"part": "run"}, registry=registry)


def push_success():
    """Only called when every stage finished. Never called on a failure."""
    push_to_gateway(config.PUSHGATEWAY, job=config.JOB,
                    grouping_key={"part": "liveness"}, registry=liveness)
