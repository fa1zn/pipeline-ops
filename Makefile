# The docker socket path differs per runtime, so it is resolved rather than assumed.
export DOCKER_HOST := $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)

TF     := terraform -chdir=terraform
VARS   := -var-file=drill.tfvars
NET    := pipeline-ops
IMAGE  := pipeline-ops/pipeline:latest

.PHONY: up down run seed drill-fail drill-stale drill-gateway alerts status fmt

up:            ## stand the whole stack up
	$(TF) init -input=false
	$(TF) apply -auto-approve $(VARS)
	@$(TF) output

down:          ## tear it down, volumes included
	$(TF) destroy -auto-approve $(VARS)

seed:          ## write synthetic upstream events
	docker run --rm --network $(NET) -e PIPELINE_DSN=postgresql://pipeline:pipeline@postgres:5432/pipeline \
	  --entrypoint python $(IMAGE) -m src.seed $(or $(N),400)

run:           ## one pipeline run
	docker run --rm --network $(NET) $(IMAGE)

drill-fail:    ## inject a transform error and page
	-docker run --rm --network $(NET) -e PIPELINE_FAULT=transform_error $(IMAGE)

drill-stale:   ## stop running and let the freshness alert fire on its own
	@echo "stop running 'make run' and wait; PipelineStale fires after the configured window"

drill-gateway: ## kill the metrics path and prove the meta-alert catches it
	docker stop $(NET)-pushgateway

alerts:        ## what actually got delivered
	@docker exec $(NET)-sink cat /var/log/alerts/alerts.jsonl 2>/dev/null || echo "nothing delivered yet"

status:        ## firing alerts straight from prometheus
	@curl -s localhost:9090/api/v1/alerts | python3 -c 'import json,sys;[print(f"{a[\"state\"]:8} {a[\"labels\"][\"alertname\"]}") for a in json.load(sys.stdin)["data"]["alerts"]]' 2>/dev/null || echo "prometheus not up"

fmt:
	$(TF) fmt -recursive
