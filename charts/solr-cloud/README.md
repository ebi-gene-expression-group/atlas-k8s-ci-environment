# Installation Guide for Solr Operator v0.9.1

## Install the CRDs (Custom Resource Definitions)

   ```bash
   kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml
   ```

## Install the Solr Operator via Helm

   ```bash
   # Add helm repo for apahce-solr
   helm repo add apache-solr https://solr.apache.org/charts
   helm repo update

   # Installing solr-operator in a namespace
   helm install solr-operator apache-solr/solr-operator --version 0.9.1 --namespace solr-operator --create-namespace
   ```

## Verify the Installation

   ```bash
   kubectl get all
   ```

## Deploying a SolrCloud

   1. Pre-requisites

   ```bash
   ENV=staging
   RELEASE=scxa
   # Create a key pair for the SolrCloud package store
   openssl genrsa -out /tmp/${RELEASE}-${ENV}-solrcloud.pem 512
   openssl rsa -in /tmp/${RELEASE}-${ENV}-solrcloud.pem -pubout -outform DER -out /tmp/${RELEASE}-${ENV}-solrcloud.der

   # Creat a namespace for the resource deployment (if it doesn't exists already)
   kubectl create namespace ${RELEASE}-${ENV}-solrcloud

   # Create the secret from the files
   kubectl -n ${RELEASE}-${ENV}-solrcloud create secret generic "solrcloud-package-store-keys" "--from-file=/tmp/${RELEASE}-${ENV}-solrcloud.pem" "--from-file=/tmp/${RELEASE}-${ENV}-solrcloud.der"
   ```

   1. Install solrCloud with helm

   ```bash
   # Install the solrCloud resource in the namespace '${RELEASE}-${ENV}-solrcloud'
   helm upgrade --install ${RELEASE}-${ENV} charts/solr-cloud \
         --namespace ${RELEASE}-${ENV}-solrcloud \
         --values charts/solr-cloud/env/${ENV}/${RELEASE}-${ENV}-solrcloud-values.yaml \
         --create-namespace=false
   ```

   1. get Solrcloud password

   ```bash
   # Get the 'admin' password
   kubectl get secret ${RELEASE}-${ENV}-solrcloud-security-bootstrap -o jsonpath='{.data.admin}' -n ${RELEASE}-${ENV}-solrcloud | base64 --decode;echo
   ```
