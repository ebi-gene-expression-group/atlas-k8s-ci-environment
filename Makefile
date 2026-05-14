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

RELEASE ?= gxa

ENV ?= test
SUPPORTED_ENVS = test staging

ENV_VALUES = charts/$(RELEASE)/values-$(ENV).yaml

# Validate environment variable (allow custom envs with values files)
ifneq ($(filter $(ENV),$(SUPPORTED_ENVS)),)
$(info Using environment: $(ENV))
else
ifeq ($(wildcard $(ENV_VALUES)),)
$(error Error: unknown ENV $(ENV). must be one of: $(SUPPORTED_ENVS) or have $(ENV_VALUES))
endif
$(info Using environment: $(ENV))
endif
NAMESPACE = $(RELEASE)-$(ENV)
APP_VERSION = 37.6.0
CURL_DEBUG_OPTS ?= --progress-bar
# Enable Helm debug dry-run mode when DEBUG is set to 1, true or yes
HELM_DEBUG_FLAGS :=
DEBUG_ENABLED := $(filter 1 true yes,$(DEBUG))
ifneq ($(DEBUG_ENABLED),)
$(info Running Helm in DEBUG dry-run mode (DEBUG=$(DEBUG)))
HELM_DEBUG_FLAGS = --debug --dry-run
endif

WAR_FILE_DIR ?= charts/$(RELEASE)/war
WAR_FILE_NAME ?= $(RELEASE).war

# Define DEPLOY_CTX_PATH based on RELEASE
ifeq ($(RELEASE),gxa)
    DEPLOY_CTX_PATH = /gxa
else ifeq ($(RELEASE),scxa)
    DEPLOY_CTX_PATH = /gxa/sc
else ifeq ($(RELEASE))
else
    $(error Error: unknown RELEASE $(RELEASE). Supported values are gxa, scxa)
endif

.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall workflow get-tomcat-users get-tomcat-user-value get-tomcat-usernames get-tomcat-passwords get-tomcat-user get-tomcat-deployer-password deploy-war get-node-info check-tomcat-users test-tomcat-manager inspect-manager-context ensure-registry-secret

# Set helm --set arguments based on environment variables
HELM_SET_ARGS = --set appVersion=$(APP_VERSION)
ifdef DOCKER_CONFIG_JSON
$(info Setting registrySecret.dockerconfigjson from DOCKER_CONFIG_JSON environment variable)
HELM_SET_ARGS += --set-file registrySecret.dockerconfigjson="$(subst ",,$(DOCKER_CONFIG_JSON))"
endif
# Check if env-specific secrets yaml exists and add as -f argument if so
SECRETS_FILE := charts/$(RELEASE)/.secrets-$(ENV).yaml
ifneq ($(wildcard $(SECRETS_FILE)),)
$(info Using secrets file: $(SECRETS_FILE))
HELM_SET_ARGS += -f $(SECRETS_FILE)
endif


deploy: init-k8s
	@echo "$(BOLD)$(GREEN)Deploying to environment: $(ENV)$(RESET)"
	@echo "$(CYAN)Using values file: $(ENV_VALUES)$(RESET)"
	helm upgrade --install \
		$(RELEASE) \
		charts/$(RELEASE) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		-f $(ENV_VALUES) \
		$(HELM_SET_ARGS) $(HELM_DEBUG_FLAGS)

deploy-test:
	$(MAKE) deploy ENV=test

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) 

# Resolved when expanded (after a recipe that depends on init-k8s), so kubectl context/namespace match init-k8s.
NODE_HOSTNAME = $(shell kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
TOMCAT_PORT = $(shell kubectl get service $(RELEASE) --namespace $(NAMESPACE) -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
TOMCAT_SERVER_URL = http://$(NODE_HOSTNAME):$(TOMCAT_PORT)
SOLR_PORT = $(shell kubectl get service $(RELEASE)-$(ENV)-solrcloud-nodeport --namespace $(RELEASE)-$(ENV)-solrcloud -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
SOLR_SERVER_URL = http://$(NODE_HOSTNAME):$(SOLR_PORT)/solr/#/

init-k8s:
	kubectx $(K8S_CONTEXT)
	kubectl config set-context --current --namespace=$(NAMESPACE)

# Workflow: deploy to test
workflow: deploy
	@echo "$(BOLD)$(GREEN)Workflow completed: deployed to $(ENV) environment$(RESET)" 

# Deploy WAR file using curl commands
deploy-war: init-k8s
	@echo "$(BOLD)$(GREEN)Deploying WAR file using curl commands...$(RESET)"
	@echo "$(BOLD)$(GREEN)Using deploy context path: $(DEPLOY_CTX_PATH)$(RESET)"
	@set -e; \
	DEPLOYER_PASSWORD=$$(kubectl get secret $(RELEASE)-secrets --namespace $(NAMESPACE) \
		-o jsonpath='{.data.tomcat-users\.xml}' \
		| base64 -d \
		| yq -p=xml '.tomcat-users.user[] | select(.["+@username"] == "deployer") | .["+@password"]'); \
	if [ -z "$$DEPLOYER_PASSWORD" ]; then \
		echo "ERROR: Failed to get deployer password"; \
		exit 1; \
	fi; \
	echo "$(BOLD)$(GREEN)Deploying WAR file... to $(TOMCAT_SERVER_URL)$(RESET)"; \
	curl --verbose -u "deployer:$$DEPLOYER_PASSWORD" \
		--fail \
		--include \
		$(CURL_DEBUG_OPTS) \
		"$(TOMCAT_SERVER_URL)/manager/text/deploy?path=$(DEPLOY_CTX_PATH)&update=true" \
		--upload-file "$(WAR_FILE_DIR)/$(WAR_FILE_NAME)"; \
	echo "$(BOLD)$(GREEN)restarting deployment on k8s...$(RESET)"; \
	kubectl rollout restart deployment $(RELEASE) --namespace $(NAMESPACE); \
	echo "$(BOLD)$(GREEN)Listing deployed applications...$(RESET)"; \
	curl -u "deployer:$$DEPLOYER_PASSWORD" \
		--fail \
		$(CURL_DEBUG_OPTS) \
		"$(TOMCAT_SERVER_URL)/manager/text/list"; \
	echo "$(BOLD)$(GREEN)Checking application homepage...$(RESET)"; \
	curl --fail \
		"$(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)" \
		--location \
		-O
	@echo "$(BOLD)$(GREEN)Checking app health check endpoint ...$(RESET)"; \
	curl --fail \
		"$(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)/json/health" \
		--location
	echo "$(BOLD)$(GREEN)Checking experiments page...$(RESET)"; \
	curl --fail \
		"$(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)/json/experiments" \
		--location \
		-O

print-env:
	@echo "$(BOLD)$(GREEN)Current Environment and Release:$(RESET)"
	@echo "ENV: $(ENV)"
	@echo "RELEASE: $(RELEASE)"


open-monitoring:
	@echo "$(BOLD)$(GREEN)Monitoring application...$(RESET)"
	@echo "url: https://grafana-hh-webadmin-35.wp-k8s.ebi.ac.uk/d/85a562078cdf77779eaa1add43ccec1e/kubernetes-compute-resources-namespace-pods?orgId=1&refresh=10s&var-datasource=default&var-cluster=&var-namespace=$(NAMESPACE)"
	open "https://grafana-hh-webadmin-35.wp-k8s.ebi.ac.uk/d/85a562078cdf77779eaa1add43ccec1e/kubernetes-compute-resources-namespace-pods?orgId=1&refresh=10s&var-datasource=default&var-cluster=&var-namespace=$(NAMESPACE)"

open-webapp: init-k8s
	@echo "$(BOLD)$(GREEN)Opening webapp...$(RESET)"
	@echo "url: $(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)"
	open "$(TOMCAT_SERVER_URL)$(DEPLOY_CTX_PATH)"

open-solr: init-k8s
	@echo "$(BOLD)$(GREEN)Opening solr...$(RESET)"
	@echo "SOLR_PORT: $(SOLR_PORT)"
	@echo "NODE_HOSTNAME: $(NODE_HOSTNAME)"
	@echo "url: $(SOLR_SERVER_URL)"
	open "$(SOLR_SERVER_URL)"
