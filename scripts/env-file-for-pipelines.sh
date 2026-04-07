#!/usr/bin/env bash

# Usage: ./generate_env_vars.sh <app> <env>
# Example: ./generate_env_vars.sh gxa staging

set -e

APP="$1"
ENV="$2"

if [ -z "$APP" ] || [ -z "$ENV" ]; then
  echo "Usage: $0 <app: gxa|scxa> <env: test|staging|prod>"
  exit 1
fi

# Get SOLR service NodePort and first node
SOLR_SVC="${APP}-${ENV}-solrcloud-nodeport"
SOLR_NS="${APP}-${ENV}-solrcloud"
SOLR_NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
SOLR_PORT=$(kubectl get svc "$SOLR_SVC" -n "$SOLR_NS" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
if [ -z "$SOLR_NODE" ] || [ -z "$SOLR_PORT" ]; then
  echo "Error: Could not resolve SOLR node/port from service $SOLR_SVC in namespace $SOLR_NS"
  set | grep SOLR_
  exit 2
fi
export SOLR_HOST="${SOLR_NODE}:${SOLR_PORT}"

# Get SOLR admin password
SOLR_SECRET="${APP}-${ENV}-solrcloud-security-bootstrap"
SOLR_PASS=$(kubectl get secret "$SOLR_SECRET" -n "$SOLR_NS" -o jsonpath='{.data.admin}' | base64 --decode)
if [ -z "$SOLR_PASS" ]; then
  echo "Error: Could not get SOLR_PASS from secret $SOLR_SECRET in namespace $SOLR_NS"
  exit 3
fi
export SOLR_PASS

# Get TOMCAT service NodePort and first node
TOMCAT_SVC="${APP}"
TOMCAT_NS="${APP}-${ENV}"
TOMCAT_NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
TOMCAT_PORT=$(kubectl get svc "$TOMCAT_SVC" -n "$TOMCAT_NS" -o jsonpath='{.spec.ports[0].nodePort}')

if [ -z "$TOMCAT_NODE" ] || [ -z "$TOMCAT_PORT" ]; then
  echo "Error: Could not resolve TOMCAT node/port from service $TOMCAT_SVC in namespace $TOMCAT_NS"
  exit 4
fi
export TOMCAT_HOST="${TOMCAT_NODE}:${TOMCAT_PORT}"

# Get TOMCAT curator user password
TOMCAT_SECRET="${APP}-secrets"
TOMCAT_USERS_XML=$(kubectl get secret "$TOMCAT_SECRET" -n "$TOMCAT_NS" -o jsonpath='{.data.tomcat-users\.xml}' | base64 --decode );
TOMCAT_USERNAME=curator
TOMCAT_P=$(echo "$TOMCAT_USERS_XML" | yq -p=xml ".tomcat-users.user[] | select(.[\"+@username\"] == \"$TOMCAT_USERNAME\") | .[\"+@password\"]")
if [ -z "$TOMCAT_P" ]; then
  echo "Error: Could not extract $TOMCAT_USERNAME password from tomcat-users.xml in secret $TOMCAT_SECRET/$TOMCAT_NS"
  exit 5
fi
export TOMCAT_USERNAME
export TOMCAT_P

# Get jdbc secrets from jdbc.properties stored in ${APP}-secrets
JDBC_SECRET="${APP}-secrets"
JDBC_NS="${APP}-${ENV}"

# Extract the base64 data for jdbc.properties from the secret
jdbc_properties_B64=$(kubectl get secret "$JDBC_SECRET" -n "$JDBC_NS" -o jsonpath='{.data.jdbc\.properties}')
if [ -z "$jdbc_properties_B64" ]; then
  echo "Error: jdbc.properties not found in secret $JDBC_SECRET in namespace $JDBC_NS"
  exit 6
fi

# Decode and parse jdbc.properties into env vars (jdbc_url, jdbc_username, jdbc_password)
jdbc_properties=$(echo "$jdbc_properties_B64" | base64 --decode)

# Helper function to get property value (avoids issues with leading/trailing spaces)
get_prop() {
    echo "$jdbc_properties" | grep -E "^[[:space:]]*$1[[:space:]]*=" | head -n1 | sed -E 's/^[[:space:]]*[^=]+[[:space:]]*=[[:space:]]*//' | sed -e 's/[[:space:]]*$//'
}

export jdbc_url="$(get_prop jdbc.url)"
export jdbc_username="$(get_prop jdbc.username)"
export jdbc_password="$(get_prop jdbc.password)"

if [ -z "$jdbc_url" ] || [ -z "$jdbc_username" ] || [ -z "$jdbc_password" ]; then
    echo "Error: Failed to extract jdbc_url, jdbc_username, or jdbc_password from jdbc.properties"
    set | grep jdbc_
    exit 7
fi
# Output environment variables
echo "copy and paste the following environment variables into your pipeline environment file:"
echo "export APP=\"${APP}\""
echo "export ENV=\"${ENV}\""
echo "export SOLR_HOST=\"${SOLR_HOST}\""
echo "export SOLR_PASS=\"${SOLR_PASS//\$/\\\$}\""
echo "export TOMCAT_HOST=\"${TOMCAT_HOST}\""
echo "export TOMCAT_P=\"${TOMCAT_P//\$/\\\$}\""
echo "export jdbc_url=\"${jdbc_url}\""
echo "export jdbc_username=\"${jdbc_username}\""
echo "export jdbc_password=\"${jdbc_password//\$/\\\$}\""