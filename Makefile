# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    $(info Loading environment variables from .env file)
    include .env
    export
else
    $(info No .env file found, using system environment variables)
endif

RELEASE ?= gxa

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
TOMCAT_SERVER_URL ?= http://localhost:8080
WAR_FILE_DIR ?= /Users/amnon/Downloads

.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall delete-jobs workflow get-tomcat-users get-tomcat-user-value get-tomcat-usernames get-tomcat-passwords get-tomcat-user get-tomcat-deployer-password deploy-war



# Set helm --set arguments based on environment variables
HELM_SET_ARGS = --set appVersion=$(APP_VERSION)
ifdef JDBC_PASSWORD
$(info Setting jdbc.password from JDBC_PASSWORD environment variable)
HELM_SET_ARGS += --set jdbc.password="$(JDBC_PASSWORD)"
endif
ifdef SOLR_PASSWORD
$(info Setting solr.password from SOLR_PASSWORD environment variable)
HELM_SET_ARGS += --set solr.password="$(SOLR_PASSWORD)"
endif
ifdef TOMCAT_DEPLOYER_PASSWORD
$(info Setting tomcat.deployerPassword from TOMCAT_DEPLOYER_PASSWORD environment variable)
HELM_SET_ARGS += --set tomcat.deployerPassword="$(TOMCAT_DEPLOYER_PASSWORD)"
endif

deploy:
	@echo using env specific values file $(ENV_VALUES)
	helm upgrade --install \
	  $(RELEASE) \
	  charts/$(RELEASE) \
	  --namespace $(NAMESPACE) \
	  --create-namespace \
	  -f $(ENV_VALUES) \
	  $(HELM_SET_ARGS)

deploy-test:
	$(MAKE) deploy ENV=test

deploy-dev:
	$(MAKE) deploy ENV=dev

deploy-prod:
	$(MAKE) deploy ENV=prod	

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) 

# Delete Kubernetes job
delete-jobs:
	@echo "Deleting Kubernetes jobs... from $(NAMESPACE)"
	# kubectl delete job $(RELEASE)-postgres-populator --namespace $(NAMESPACE) || true
	kubectl delete job $(RELEASE)-solrcloud-bioentities-jsonl --namespace $(NAMESPACE) || true
	kubectl delete job bioentities-populator --namespace $(NAMESPACE) || true
	kubectl delete job $(RELEASE)-solrcloud-bulk-analytics-jsonl --namespace $(NAMESPACE) || true
	# kubectl delete job $(RELEASE)-solrcloud-bulk-analytics-populator --namespace $(NAMESPACE) || true

# Workflow: delete job then deploy to test
workflow: delete-jobs deploy-test
	@echo "Workflow completed: job deleted and deployed to test environment" 

# Get tomcat-users.xml from $(RELEASE)-secrets secret
get-tomcat-deployer-password:
	@echo "Extracting deployer password from tomcat-users.xml from $(RELEASE)-secrets secret
	@kubectl get secret $(RELEASE)-secrets --namespace $(NAMESPACE) \
		-o jsonpath='{.data.tomcat-users\.xml}' \
		| base64 -d \
		| yq -oy -p=xml \
			'.tomcat-users.user | select(.["+@username"] == "deployer") | .+@password'

# Deploy WAR file using curl commands
deploy-war:
	@echo "Deploying WAR file using curl commands..."
	@DEPLOYER_PASSWORD=$$(kubectl get secret $(RELEASE)-secrets --namespace $(NAMESPACE) \
		-o jsonpath='{.data.tomcat-users\.xml}' \
		| base64 -d \
		| yq -oy -p=xml \
			'.tomcat-users.user | select(.["+@username"] == "deployer") | .+@password'); \
	echo "Deploying WAR file..."; \
	curl -u deployer:$$DEPLOYER_PASSWORD \
		--fail \
		--include \
		--verbose \
		-X PUT \
		"$(TOMCAT_SERVER_URL)/manager/text/deploy?path=/gxa&update=true" \
		--upload-file $(WAR_FILE_DIR)/gxa.war; \
	echo "Listing deployed applications..."; \
	curl -u deployer:$$DEPLOYER_PASSWORD \
		--verbose \
		"$(TOMCAT_SERVER_URL)/manager/text/list"; \
	echo "Checking application location..."; \
	curl "$(TOMCAT_SERVER_URL)/gxa" \
		--location

