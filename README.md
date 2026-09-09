# pipeline-ops

A nightly batch pipeline with the infrastructure and the alerting that a batch
job actually needs, all of it declared in Terraform.

    make up      # 21 resources: postgres, pushgateway, prometheus, alertmanager, grafana, sink, the job image
    make seed    # synthetic upstream events, some of them backdated
    make run     # one pipeline run
    make status  # what is firing
    make alerts  # what actually reached the pager

## Why it exists

Batch jobs break the assumptions monitoring is usually built on, and the usual
setup fails silently rather than loudly. This is a small system where those
failures are reproducible on demand, and `docs/INCIDENT-2026-09-08.md` records
four drills, three of which found a defect in the alerting rather than in the
pipeline.

## The three ideas

**A stopped job emits nothing.** A failure counter cannot see the outage where
the job never starts. So the primary alert is a timestamp going stale, not an
error going up: `time() - pipeline_last_success_timestamp_seconds > 26h`. This
catches a broken scheduler, a full disk, and an image that will not pull, none of
which produce a failure to count.

**Job liveness and data freshness are different questions.** A run can succeed on
schedule every night for a week while upstream is dead. `pipeline_watermark_lag_seconds`
is the only thing in the stack that notices, and it pages separately.

**Counters are wrong through a pushgateway.** The job starts a fresh registry
every run and the push replaces the group, so a counter never climbs and
`increase()` returns zero no matter how many times the job ran. Everything here
is a gauge describing the last run.

## Layout

    terraform/
      main.tf                  templated configs, module wiring, the readiness gate
      variables.tf             thresholds and ports, all of them variables
      drill.tfvars             production rules on a stopwatch, so a drill finishes while you watch
      modules/stack/           containers, volumes, network, the job image
      modules/grafana_config/  datasource, folder and dashboard as HCL, not a pasted export
    pipeline/src/
      metrics.py               the metric contract, and why each metric is the type it is
      stages.py                ingest, transform, publish; each safe to run twice
      run.py                   stage orchestration, run log, exit codes
    observability/
      prometheus/rules/        six alerts, templated from tfvars
      alertmanager/            routing and inhibition
      sink/                    stands in for PagerDuty, so a drill leaves evidence
    docs/INCIDENT-2026-09-08.md

## Things worth knowing before changing it

**Thresholds are variables, not constants.** The production values are hours.
Nobody will sit and watch an hour pass to check a rule works, so `drill.tfvars`
shortens the same rules to seconds. The rules themselves do not change.

**Every mounted config is in `config_fingerprint`.** Terraform tracks containers,
not the bytes inside a bind-mounted file, so without this an edit to
`alertmanager.yml` applies cleanly, reports zero changes, and leaves the old
config running. That was drill 4, and it is the only one of the four failures
that reported success.

**Cardinality is bounded on purpose.** `stage` takes three values and nothing
carries a run id. A per-run label adds a series per run and never stops.

**The Grafana provider talks to a server this same apply creates.** Terraform
cannot make a provider depend on a resource, so `terraform_data.grafana_ready`
polls `/api/health` and every Grafana resource depends on it.

## The pipeline

Three stages, all of them safe to run twice.

`ingest` reads upstream from the watermark **minus a lookback**, not from the
watermark. Upstream stamps rows at event time and they can land out of order, so
starting at the watermark drops every late row. Re-reading a window costs nothing
because the insert is idempotent on the upstream id.

`transform` is a pure function of the raw table, so a bad deploy is recovered by
deleting from `derived_events` and running again. It never asks upstream for
anything.

`publish` records how far behind the data is, which is deliberately separate from
whether the run succeeded.
