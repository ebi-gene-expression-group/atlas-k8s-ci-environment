# Color definitions
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
MAGENTA := \033[0;35m
CYAN := \033[0;36m
WHITE := \033[0;37m
RESET := \033[0m
BOLD := \033[1m

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    $(info Loading environment variables from .env file)
    # Generate a processed env file (strip surrounding double quotes, trim, ignore comments) and include it
    include .env
    export
else
    $(info No .env file found, using system environment variables)
endif

RELEASE ?= scxa

# Define DEPLOY_CTX_PATH based on RELEASE
ifeq ($(RELEASE),gxa)
    DEPLOY_CTX_PATH = /gxa
else ifeq ($(RELEASE),scxa)
    DEPLOY_CTX_PATH = /gxa/sc
else
    $(error Error: unknown RELEASE $(RELEASE). Supported values are gxa or scxa)
endif
$(info Using deploy context path: $(DEPLOY_CTX_PATH))

ENV ?= test
# SUPPORTED_ENVS = test dev prod
SUPPORTED_ENVS = test

# Validate environment variable
ifeq ($(filter $(ENV),$(SUPPORTED_ENVS)),)
$(error Error: unknown ENV $(ENV). must be one of: $(SUPPORTED_ENVS))
endif
$(info Using environment: $(ENV))

ENV_VALUES = charts/$(RELEASE)/values-$(ENV).yaml
NAMESPACE = $(RELEASE)-$(ENV)
APP_VERSION = 37.0.5

# Simple variables for node hostname and port
NODE_HOSTNAME ?= $(shell kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
NODE_PORT ?= $(shell kubectl get service $(RELEASE) --namespace $(NAMESPACE) -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
TOMCAT_SERVER_URL ?= http://$(NODE_HOSTNAME):$(NODE_PORT)

WAR_FILE_DIR ?= charts/$(RELEASE)/war
.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall delete-jobs workflow get-tomcat-users get-tomcat-user-value get-tomcat-usernames get-tomcat-passwords get-tomcat-user get-tomcat-deployer-password deploy-war get-node-info check-tomcat-users test-tomcat-manager inspect-manager-context


# Set helm --set arguments based on environment variables
HELM_SET_ARGS = --set appVersion=$(APP_VERSION)
ifdef JDBC_PASSWORD
$(info Setting jdbc.password from JDBC_PASSWORD environment variable)
HELM_SET_ARGS += --set jdbc.password="$(subst ",,$(JDBC_PASSWORD))"
endif
ifdef SOLR_PASSWORD
$(info Setting solr.password from SOLR_PASSWORD environment variable)
HELM_SET_ARGS += --set solr.password="$(subst ",,$(SOLR_PASSWORD))"
endif
ifdef TOMCAT_DEPLOYER_PASSWORD
$(info Setting tomcat.deployerPassword from TOMCAT_DEPLOYER_PASSWORD environment variable)
HELM_SET_ARGS += --set tomcat.deployerPassword="$(subst ",,$(TOMCAT_DEPLOYER_PASSWORD))"
endif
ifdef DOCKER_CONFIG_JSON
$(info Setting registrySecret.dockerconfigjson from DOCKER_CONFIG_JSON environment variable)
HELM_SET_ARGS += --set-file registrySecret.dockerconfigjson="$(subst ",,$(DOCKER_CONFIG_JSON))"
endif

deploy:
	@echo "$(BOLD)$(GREEN)Deploying to environment: $(ENV)$(RESET)"
	@echo "$(CYAN)Using values file: $(ENV_VALUES)$(RESET)"
	helm upgrade --install \
	  $(RELEASE) \
	  charts/$(RELEASE) \
	  --namespace $(NAMESPACE) \
	  --create-namespace \
	  -f $(ENV_VALUES) \
	  $(HELM_SET_ARGS)

deploy-test:
	$(MAKE) deploy ENV=test

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) 

# Delete Kubernetes job
delete-jobs:
	@echo "$(BOLD)$(MAGENTA)Deleting Kubernetes jobs... from $(NAMESPACE)$(RESET)"

	kubectl delete job --selector app.kubernetes.io/name=$(RELEASE) --namespace $(NAMESPACE) || true

# Workflow: delete job then deploy to test
workflow: delete-jobs deploy-test
	@echo "$(BOLD)$(GREEN)Workflow completed: job deleted and deployed to test environment$(RESET)" 

# Deploy WAR file using curl commands
deploy-war:
	@echo "$(BOLD)$(GREEN)Deploying WAR file using curl commands...$(RESET)"
	@set -e; \
	DEPLOYER_PASSWORD=$$(kubectl get secret $(RELEASE)-secrets --namespace $(NAMESPACE) \
		-o jsonpath='{.data.tomcat-users\.xml}' \
		| base64 -d \
		| yq -oy -p=xml \
			'.tomcat-users.user | select(.["+@username"] == "deployer") | .+@password'); \
	if [ -z "$$DEPLOYER_PASSWORD" ]; then \
		echo "ERROR: Failed to get deployer password"; \
		exit 1; \
	fi; \
	echo "Deploying WAR file... to $(TOMCAT_SERVER_URL)"; \
	curl -u deployer:$$DEPLOYER_PASSWORD \
		--fail \
		--include \
		--verbose \
		"$(TOMCAT_SERVER_URL)/manager/text/deploy?path=$(DEPLOY_CTX_PATH)&update=true" \
		--upload-file $(WAR_FILE_DIR)/gxa.war; \
	echo "Listing deployed applications..."; \
	curl -u deployer:$$DEPLOYER_PASSWORD \
		--fail \
		--verbose \
		"$(TOMCAT_SERVER_URL)/manager/text/list"; \
	echo "Checking application homepage..."; \
	curl --fail \
		"$(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)" \
		--location \
		-O

