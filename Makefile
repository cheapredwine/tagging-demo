.PHONY: demo setup tag get filter delete bulk deploy test clean help

# ------------------------------------------------------------------
# Cloudflare Resource Tagging — Demo Makefile
# ------------------------------------------------------------------
# The interactive demo script is the recommended starting point.
# ------------------------------------------------------------------

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

demo: ## Run the interactive demo (recommended)
	@bash demo.sh

setup: ## Validate environment and token only
	@bash setup.sh

tag: ## Tag a resource (usage: make tag TYPE=worker ID=my-worker K="env=prod team=sre")
	@if [ -z "$(TYPE)" ] || [ -z "$(ID)" ] || [ -z "$(K)" ]; then \
		echo "Usage: make tag TYPE=worker ID=my-worker K=\"env=prod team=sre\""; \
		exit 1; \
	fi
	@bash -c './scripts/tag-resource.sh -t $(TYPE) -r $(ID) $(K)'

get: ## Get tags for a resource (usage: make get TYPE=worker ID=my-worker)
	@if [ -z "$(TYPE)" ] || [ -z "$(ID)" ]; then \
		echo "Usage: make get TYPE=worker ID=my-worker"; \
		exit 1; \
	fi
	@./scripts/get-tags.sh -t $(TYPE) -r $(ID)

filter: ## Filter resources by tag (usage: make filter Q="env:prod" [TYPE=worker])
	@if [ -z "$(Q)" ]; then \
		echo "Usage: make filter Q=\"env:prod\""; \
		exit 1; \
	fi
	@./scripts/filter-resources.sh $(if $(TYPE),-t $(TYPE)) "$(Q)"

delete: ## Delete all tags on a resource (usage: make delete TYPE=worker ID=my-worker)
	@if [ -z "$(TYPE)" ] || [ -z "$(ID)" ]; then \
		echo "Usage: make delete TYPE=worker ID=my-worker"; \
		exit 1; \
	fi
	@./scripts/delete-tags.sh -t $(TYPE) -r $(ID)

bulk: ## Bulk-tag multiple resources (usage: make bulk TYPE=worker KEY=env VAL=prod IDS="a b c")
	@if [ -z "$(TYPE)" ] || [ -z "$(KEY)" ] || [ -z "$(VAL)" ] || [ -z "$(IDS)" ]; then \
		echo "Usage: make bulk TYPE=worker KEY=env VAL=prod IDS=\"w1 w2 w3\""; \
		exit 1; \
	fi
	@./scripts/bulk-tag.sh $(TYPE) $(KEY) $(VAL) $(IDS)

# ------------------------------------------------------------------
# Worker deployment (used internally by demo.sh)
# ------------------------------------------------------------------

deploy: ## Deploy the self-tagging Worker
	@cd worker && npx wrangler deploy

test: ## Quick smoke-test against deployed Worker
	@echo "GET  /"
	@curl -sS https://$(or $(WORKER_NAME),tagging-demo-worker).$(or $(SUBDOMAIN),workers.dev)/ | head -20
	@echo ""
	@echo "GET  /tags"
	@curl -sS https://$(or $(WORKER_NAME),tagging-demo-worker).$(or $(SUBDOMAIN),workers.dev)/tags
	@echo ""

clean: ## Remove local temp files
	@rm -f *.log
