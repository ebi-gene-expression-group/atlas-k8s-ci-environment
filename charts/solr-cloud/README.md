#README

Step-by-Step Installation Guide for Solr Operator v0.8.1

1. Install the CRDs (Custom Resource Definitions)

   kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.8.1/all-with-dependencies.yaml

2. Install the Solr Operator via Helm

   # Add helm repo for apahce-solr
   helm repo add apache-solr https://solr.apache.org/charts
   helm repo update

   # Installing solr-operator in a namespace
   helm install solr-operator apache-solr/solr-operator --version 0.8.1 --namespace solr --create-namespace

3. Verify the Installation

   kubectl get all

4. Deploying a SolrCloud

   a. Pre-requisites

     # Create a key pair for the SolrCloud package store

     openssl genrsa -out /tmp/gxa-solrcloud.pem 512
     openssl rsa -in /tmp/gxa-solrcloud.pem -pubout -outform DER -out /tmp/gxa-solrcloud.der

     # Create the secret from the files
     kubectl -n solr create secret generic gxa-solrcloud-package-store-keys --from-file=/tmp/gxa-solrcloud.pem --from-file=/tmp/gxa-solrcloud.der 


   b. Install solrCloud with helm
   
      # Install the solrCloud resource in the namespace 'solr'
      helm install gxa-solr charts/solr-cloud/Charts.yaml --namespace solr --create-namespace=false
