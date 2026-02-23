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
else ifeq ($(RELEASE),bioentities-collection)
else
    $(error Error: unknown RELEASE $(RELEASE). Supported values are gxa, scxa or bioentities-collection)
endif
$(info Using deploy context path: $(DEPLOY_CTX_PATH))

ENV ?= test
# SUPPORTED_ENVS = test dev prod
SUPPORTED_ENVS = test

ENV_VALUES = charts/$(RELEASE)/values-$(ENV).yaml

# Validate environment variable (allow custom envs with values files)
ifneq ($(filter $(ENV),$(SUPPORTED_ENVS)),)
$(info Using environment: $(ENV))
else
ifeq ($(wildcard $(ENV_VALUES)),)
$(error Error: unknown ENV $(ENV). must be one of: $(SUPPORTED_ENVS) or have $(ENV_VALUES))
endif
$(info Using custom environment: $(ENV))
endif
NAMESPACE = $(RELEASE)-$(ENV)
APP_VERSION = 37.6.0
CURL_DEBUG_OPTS=--progress-bar
# Enable Helm debug dry-run mode when DEBUG is set to 1, true or yes
HELM_DEBUG_FLAGS :=
DEBUG_ENABLED := $(filter 1 true yes,$(DEBUG))
ifneq ($(DEBUG_ENABLED),)
$(info Running Helm in DEBUG dry-run mode (DEBUG=$(DEBUG)))
HELM_DEBUG_FLAGS = --debug --dry-run
endif
# Simple variables for node hostname and port
NODE_HOSTNAME ?= $(shell kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
NODE_PORT ?= $(shell kubectl get service $(RELEASE) --namespace $(NAMESPACE) -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
TOMCAT_SERVER_URL ?= http://$(NODE_HOSTNAME):$(NODE_PORT)

WAR_FILE_DIR ?= charts/$(RELEASE)/war
WAR_FILE_NAME ?= gxa.war
.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall workflow get-tomcat-users get-tomcat-user-value get-tomcat-usernames get-tomcat-passwords get-tomcat-user get-tomcat-deployer-password deploy-war get-node-info check-tomcat-users test-tomcat-manager inspect-manager-context ensure-registry-secret


# Set helm --set arguments based on environment variables
HELM_SET_ARGS = --set appVersion=$(APP_VERSION)
ifdef JDBC_PASSWORD
$(info Setting jdbc.password and bioentities-collection.jdbc.password from JDBC_PASSWORD environment variable)
HELM_SET_ARGS += --set jdbc.password="$(subst ",,$(JDBC_PASSWORD))"
HELM_SET_ARGS += --set bioentities-collection.jdbc.password="$(subst ",,$(JDBC_PASSWORD))"
endif
ifdef SOLR_PASSWORD
$(info Setting solr.password and bioentities-collection.solr.password from SOLR_PASSWORD environment variable)
HELM_SET_ARGS += --set solr.password="$(subst ",,$(SOLR_PASSWORD))"
HELM_SET_ARGS += --set bioentities-collection.solr.password="$(subst ",,$(SOLR_PASSWORD))"
endif
ifdef TOMCAT_DEPLOYER_PASSWORD
$(info Setting tomcat.deployerPassword from TOMCAT_DEPLOYER_PASSWORD environment variable)
HELM_SET_ARGS += --set tomcat.deployerPassword="$(subst ",,$(TOMCAT_DEPLOYER_PASSWORD))"
endif
ifdef TOMCAT_CURATOR_PASSWORD
$(info Setting tomcat.curatorPassword from TOMCAT_CURATOR_PASSWORD environment variable)
HELM_SET_ARGS += --set tomcat.curatorPassword="$(subst ",,$(TOMCAT_CURATOR_PASSWORD))"
endif
ifdef DOCKER_CONFIG_JSON
$(info Setting registrySecret.dockerconfigjson from DOCKER_CONFIG_JSON environment variable)
HELM_SET_ARGS += --set-file registrySecret.dockerconfigjson="$(subst ",,$(DOCKER_CONFIG_JSON))"
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

init-k8s:
	kubectx $(K8S_CONTEXT)
	kubectl config set-context --current --namespace=$(NAMESPACE)

# Workflow: deploy to test
workflow: deploy-test
	@echo "$(BOLD)$(GREEN)Workflow completed: deployed to test environment$(RESET)" 

# Deploy WAR file using curl commands
deploy-war: init-k8s
	@echo "$(BOLD)$(GREEN)Deploying WAR file using curl commands...$(RESET)"
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
	curl -u "deployer:$$DEPLOYER_PASSWORD" \
		--fail \
		--include \
		$(CURL_DEBUG_OPTS) \
		"$(TOMCAT_SERVER_URL)/manager/text/deploy?path=/gxa&update=true" \
		--upload-file "$(WAR_FILE_DIR)/$(WAR_FILE_NAME)"; \
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
		"$(TOMCAT_SERVER_URL)/gxa/json/health" \
		--location
	echo "$(BOLD)$(GREEN)Checking experiments page...$(RESET)"; \
	curl --fail \
		"$(TOMCAT_SERVER_URL)/gxa/json/experiments" \
		--location \
		-O
