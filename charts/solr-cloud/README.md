# README

Step-by-Step Installation Guide for Solr Operator v0.9.1

1. Install the CRDs (Custom Resource Definitions)
   
   ```bash
   kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml

2. Install the Solr Operator via Helm

   ```bash
   # Add helm repo for apahce-solr
   helm repo add apache-solr https://solr.apache.org/charts
   helm repo update

   # Installing solr-operator in a namespace
   helm install solr-operator apache-solr/solr-operator --version 0.9.1 --namespace solr-operator --create-namespace

3. Verify the Installation

   ```bash
   kubectl get all

4. Deploying a SolrCloud

   ```bash
   a. Pre-requisites

     # Create a key pair for the SolrCloud package store
     openssl genrsa -out /tmp/gxa-solrcloud.pem 512
     openssl rsa -in /tmp/gxa-solrcloud.pem -pubout -outform DER -out /tmp/gxa-solrcloud.der


     # Creat a namespace for the resource deployment (if it doesn't exists already)
     kubectl create namespace gxa-dev-solrcloud

     # Create the secret from the files
     kubectl -n gxa-dev-solrcloud create secret generic gxa-solrcloud-package-store-keys --from-file=/tmp/gxa-solrcloud.pem --from-file=/tmp/gxa-solrcloud.der

   b. Install solrCloud with helm
 
     # Install the solrCloud resource in the namespace 'gxa-dev-solrcloud'
     helm install gxa-dev charts/solr-cloud \
          --namespace gxa-dev-solrcloud \
          --values charts/solr-cloud/env/dev/gxa-dev-solrcloud-values.yaml \
          --create-namespace=false

     # Install the solrCloud resource in the namespace 'scxa-dev-solrcloud'
     helm install scxa-dev charts/solr-cloud \
          --namespace scxa-dev-solrcloud \
          --values charts/solr-cloud/env/dev/scxa-dev-solrcloud-values.yaml \
          --create-namespace=false

   c. Solrcloud password

     # Get the 'admin' password
     kubectl get secret gxa-dev-solrcloud-security-bootstrap -o jsonpath='{.data.admin}' -n gxa-dev-solrcloud | base64 --decode;echo
