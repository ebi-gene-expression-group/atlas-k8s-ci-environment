RELEASE ?= gxa

ENV ?= test
# SUPPORTED_ENVS = test dev prod
SUPPORTED_ENVS = test

ENV_VALUES = charts/$(RELEASE)/values-$(ENV).yaml
NAMESPACE = $(RELEASE)-$(ENV)
APP_VERSION = 37.0.5
TOMCAT_SERVER_URL ?= http://localhost:8080
WAR_FILE_DIR ?= /Users/amnon/Downloads

.PHONY: deploy deploy-test deploy-dev deploy-prod uninstall validate-env delete-job workflow get-tomcat-users get-tomcat-user-value get-tomcat-usernames get-tomcat-passwords get-tomcat-user get-tomcat-deployer-password deploy-war

# Validate environment variable
validate-env:
	@if ! echo "$(SUPPORTED_ENVS)" | grep -wq "$(ENV)"; then \
	  echo "Error: unknown ENV $(ENV). must be one of: $(SUPPORTED_ENVS)"; \
	  exit 1; \
	fi
	@echo "Environment validation passed: $(ENV)"

deploy: validate-env
	@echo deploying to env $(ENV)
	@echo using env specific values file $(ENV_VALUES)
	helm upgrade --install \
	  $(RELEASE) \
	  charts/$(RELEASE) \
	  --namespace $(NAMESPACE) \
	  --create-namespace \
	  -f $(ENV_VALUES) \
	  --set appVersion=$(APP_VERSION)

deploy-test:
	$(MAKE) deploy ENV=test

deploy-dev:
	$(MAKE) deploy ENV=dev

deploy-prod:
	$(MAKE) deploy ENV=prod	

uninstall:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE) 

# Delete Kubernetes job
delete-jobs: validate-env
	@echo "Deleting Kubernetes jobs... from $(NAMESPACE)"
	# kubectl delete job $(RELEASE)-postgres-populator --namespace $(NAMESPACE) || true
	# kubectl delete job $(RELEASE)-solrcloud-bioentities-jsonl --namespace $(NAMESPACE) || true
	kubectl delete job $(RELEASE)-solrcloud-bulk-analytics-jsonl --namespace $(NAMESPACE) || true
	# kubectl delete job $(RELEASE)-solrcloud-bulk-analytics-populator --namespace $(NAMESPACE) || true

# Workflow: delete job then deploy to test
workflow: validate-env delete-jobs deploy-test
	@echo "Workflow completed: job deleted and deployed to test environment" 

# Get tomcat-users.xml from $(RELEASE)-secrets secret
get-tomcat-deployer-password: validate-env
	@echo "Extracting deployer password from tomcat-users.xml from $(RELEASE)-secrets secret
	@kubectl get secret $(RELEASE)-secrets --namespace $(NAMESPACE) \
		-o jsonpath='{.data.tomcat-users\.xml}' \
		| base64 -d \
		| yq -oy -p=xml \
			'.tomcat-users.user | select(.["+@username"] == "deployer") | .+@password'

# Deploy WAR file using curl commands
deploy-war: validate-env
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

