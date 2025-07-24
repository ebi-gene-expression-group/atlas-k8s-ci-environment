RELEASE ?= gxa

ENV ?= test
SUPPORTED_ENVS = test dev prod

TOMCAT_PASSWORD ?= $(shell openssl rand -base64 16)

VALUES = charts/$(RELEASE)/values-$(ENV).yaml
NAMESPACE = $(RELEASE)-$(ENV)

.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall

deploy:

	@if ! echo "$(SUPPORTED_ENVS)" | grep -wq "$(ENV)"; then \
	  echo "Error: ENV must be one of: $(SUPPORTED_ENVS)"; \
	  exit 1; \
	fi
	helm upgrade --install \
	  $(RELEASE) \
	  charts/$(RELEASE) \
	  --namespace $(NAMESPACE) \
	  --create-namespace \
	  -f $(VALUES) \
	  --set tomcat.deployerPassword="$(TOMCAT_PASSWORD)"

deploy-test:
	$(MAKE) deploy ENV=test

deploy-dev:
	$(MAKE) deploy ENV=dev

deploy-prod:
	$(MAKE) deploy ENV=prod

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) 