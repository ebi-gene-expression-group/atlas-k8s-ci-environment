#!/bin/bash
# Point to the internal API server hostname
APISERVER=https://kubernetes.default.svc
# Path to ServiceAccount token
SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount
# Read this Pod's namespace
NAMESPACE=$(cat ${SERVICEACCOUNT}/namespace)
# Read the ServiceAccount bearer token
TOKEN=$(cat ${SERVICEACCOUNT}/token)
# Reference the internal certificate authority (CA)
CACERT=${SERVICEACCOUNT}/ca.crt

REPLICAS_DESIRED=0

function get_stateful_replicas() {
  echo $( kubectl get statefulset $1 -o=jsonpath="{.spec.replicas}" )
}

function decrease_replicas() {
  for replicaset in $*
  do
    replicasetresponse=$(get_stateful_replicas $replicaset)
    echo "$replicaset"
    echo "Replica set query result: $replicasetresponse"
    if [ $replicasetresponse -eq 0 ]
    then
      echo "No replicas running. Doing nothing..."
    else
      echo "$replicaset running, and no jenkins nodes running. Scaling down...."
      echo "Running: kubectl scale statefulset $replicaset --replicas=$REPLICAS_DESIRED"
      scale_result=$( kubectl scale statefulset $replicaset --replicas=$REPLICAS_DESIRED )
      echo $scale_result
    fi
  done
}

jenkins_pods=$( kubectl get pods -l "$LABELS_FILTER"  -o=jsonpath="{.items[*].metadata.name}" )
echo "Jenkins pods running [$jenkins_pods]"

if [ -z "$jenkins_pods" ]
then
    echo "0 jenkins pods found"
    decrease_replicas $STATEFULSET
else
    echo "Can't decrease resources, Jenkins nodes running"
fi