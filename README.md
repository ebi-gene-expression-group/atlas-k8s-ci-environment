# atlas-k8s-ci-environment
Collection of Kubernetes manifests for CI of Expression Atlas web applications


## Prologue
### Populating read-only volumes
In order to run tests on multiple branches concurrently we need to set up read-only volumes. The pattern we follow to
populate them with data is described in the following document:
https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/readonlymany-disks

This can be generalised to vendors other than Google Cloud Platform. However, the first step requires creating a
snapshot class with a **`driver` which is platform-specific**. In the remainder of this document this snapshot class 
will be used to create snapshots of read-write volumes.For GCP this is in the top-level directory of this repo:
```bash
kubectl create -f snapshot-class.yaml
```

### Regions and zones
It’s important to know that for a pod to be successfully scheduled in a cluster, all volumes must be in the same zone.
A pod can’t mount multiple volumes across different zones. Since read-only volumes are created when a pod requests it
for the first time, the zone of the volume will be the one where the pod is scheduled; these are set with
`nodeSelector` to `europe-west2-a`:
```yaml
spec:
  template:
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: "europe-west2-a"
```

This ensures all the read-only volumes will be created in the same zone and any pod that needs them can be scheduled.
Additionally, it’s a good idea to set the region with the `gcloud` command when deploying the manifests as a safeguard:
```bash
gcloud config set compute/zone europe-west2-a
```

### Inspecting volumes
You can browse the contents of the populated volumes at any point with a pod that mounts the volume. The file 
`ubuntu-pod.yaml` is provided for convenience (the pod will be up for thirty minutes before shutting down). Just
replace the value of the `claimName` with the one corresponding to the volume want to inspect.
```bash
kubectl create -f - <<EOF
# Paste YAML contents or use `kubectl create -f ubuntu-pod.yaml`
EOF
```

Next, open a shell in the pod:
```bash
kubectl -n jenkins-gene-expression wait --for=condition=ready --timeout=1h pod ubuntu && \
kubectl -n jenkins-gene-expression exec -it ubuntu -- bash
```

If you used `ubuntu-pod.yaml`, the volume will be mounted in the `/foobar` directory.

Remember to clean up or wait for half an hour for the pod to shut down: 
```bash
kubectl -n jenkins-gene-expression delete pod ubuntu
```

### Inspecting Solr in GKE
The following command will forward port 8983 of the Solr pods that back the SolrCloud headless service (this service is
created by the Solr Operator and is named `gxa-solrcloud-headless` in the case of bulk).
```bash
gcloud container clusters get-credentials dev-autopilot-cluster --region europe-west2 --project prj-int-dev-atlas-app-intg && \
echo "# When the next line says 'Forwarding from...', go to: https://ssh.cloud.google.com/devshell/proxy?port=8080" && \
kubectl port-forward --namespace jenkins-gene-expression $(kubectl get pod --namespace jenkins-gene-expression --selector="solr-cloud=gxa,technology=solr-cloud" --output jsonpath='{.items[0].metadata.name}') 8080:8983
```

As stated by the `echo` statement, this will allow you to access the Solr admin interface at
`https://ssh.cloud.google.com/devshell/proxy?port=8080`. You can read more about how to access VMs securely at
https://cloud.google.com/solutions/connecting-securely.


## Bioentity Properties
Both bulk Expression Atlas and Single Cell Expression Atlas require a `bioentities` collection in their respective
SolrCloud clusters for some integration tests. In the case of bulk, though, this collection needs to be populated
before populating the `bulk-analytics` collection because the latter reads gene annotations from the former.

The first step for either project is to create a read-only volume of the `bioentity-properties` directory. For this we
start by creating an empty read-write volume, then we run a job that downloads the data via FTP, we wait until the job
completes before we create a snapshot of the read-write volume, and finally we create a read-only volume from the
snapshot.
```bash
cd bioentity-properties
kubectl create -f bioentity-properties-rwo-pvc.yaml && \
kubectl create -f bioentity-properties-populator-job.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=1h job bioentity-properties-populator && \
kubectl create -f bioentity-properties-rwo-snapshot.yaml && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot bioentity-properties-rwo-snapshot && \
kubectl create -f bioentity-properties-rox-pvc.yaml
```

Note that the timeouts for the `wait` command are only indicative. They may need to be adjusted depending on the speed 
of the underlying storage and network connection.

## Gradle Read-Only Dependency Cache Volume
To speed up test builds [it is very convenient to have a Gradle Read Only Dependency Cache volume]
(https://docs.gradle.org/current/userguide/dependency_resolution.html#sub:ephemeral-ci-cache). This can be created
as follows:
```bash
cd gradle-ro-dep-cache
kubectl create -f gradle-ro-dep-cache-rwo-pvc.yaml && \
kubectl create -f gradle-ro-dep-cache-populator-job.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=1h job gradle-ro-dep-cache-populator && \
kubectl create -f gradle-ro-dep-cache-rwo-snapshot.yaml && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot gradle-7.0-ro-dep-cache-rwo-snapshot && \
kubectl create -f gradle-ro-dep-cache-rox-pvc.yaml
```

Inside the populator job we don’t care about the success or failure of the tasks. We just want to make Gradle download
all dependencies to copy them to the read-write volume. Similar to the previous section, we then create a snapshot of
the read-write volume and finally create a read-only volume from the snapshot.


## Gene Expression Atlas
# Data volumes
The first step specific to (bulk) Gene Expression Atlas is to create two read-only volumes of the test datasets and the
ontology auxiliary files, respectively. As before, we create and populate read-write volumes, and we create a read-only
volume from snapshots.
```bash
cd gxa-data
kubectl create -f gxa-data-rwo-pvc.yaml && \
kubectl create -f gxa-data-populator-job.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=6h job gxa-data-populator && \
kubectl create -f gxa-data-rwo-snapshot.yaml && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=1h volumesnapshot gxa-data-rwo-snapshot && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot gxa-data-ontology-rwo-snapshot && \
kubectl create -f gxa-data-rox-pvc.yaml
```

Be careful if you are using the Google Cloud Shell, since it can lose the connection after some time of inactivity. If
this happens, you can paste the above commands from one of the `wait` commands. Another alternative is to run them
with [`nohup`](https://man7.org/linux/man-pages/man1/nohup.1.html).


# PostgreSQL
In order to create the JSONL files to populate the `bulk-analytics` collection, experiments need to be loaded in 
Postgres. The CLI module reuses a great deal of the logic from the web application for this purpose, so if an
experiment isn’t loaded the CLI will throw an error reporting that the experiment doesn’t exist. This is why we need to
load the experiments in Postgres; as a side benefit, the process will also create the experiment design files which are
also needed for the integration tests.

This step creates a Postgres deployment, a job that migrates the schema to the latest version with Flyway, a job that
loads the experiments, and the creation of a read-only volume for the experiment design files:
```bash
cd gxa-postgres
kubectl create -f gxa-postgres-deployment.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=30m job gxa-postgres-migrator && \
kubectl create -f gxa-postgres-populator.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=1h job gxa-postgres-populator && \
kubectl create -f gxa-expdesign/gxa-expdesign-rwo-snapshot.yaml && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot gxa-expdesign-rwo-snapshot && \
kubectl create -f gxa-expdesign/gxa-expdesign-rox-pvc.yaml
```

# Solr
Create a key pair for the SolrCloud package store:
```bash
openssl genrsa -out ./gxa-solrcloud.pem 512
openssl rsa -in ./gxa-solrcloud.pem -pubout -outform DER -out ./gxa-solrcloud.der
kubectl -n jenkins-gene-expression create secret generic gxa-solrcloud-package-store-keys \
--from-file=./gxa-solrcloud.pem \
--from-file=./gxa-solrcloud.der
```

Install the [Solr Operator](https://solr.apache.org/operator/).

[Load the image used by the jobs to Quay](https://docs.quay.io/solution/getting-started.html):
```bash
docker build -t gxa-atlas-web-bulk-postgres-solrcloud-populator .
docker run gxa-atlas-web-bulk-postgres-solrcloud-populator
docker commit <CONTAINER_ID> quay.io/ebigxa/gxa-atlas-web-bulk-postgres-solrcloud-populator
docker push quay.io/ebigxa/gxa-atlas-web-bulk-postgres-solrcloud-populator:latest
```

Create a SolrCloud cluster:
```bash
cd gxa-solrcloud
kubectl create -f gxa-solrcloud.yaml
```

## Bioentities
```bash
cd gxa-solrcloud/bioentities
kubectl create -f gxa-solrcloud-bioentities-jsonl.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=30m job gxa-solrcloud-bioentities-jsonl && \
kubectl create -f gxa-solrcloud-bioentities-populator.yaml
```

## Bulk Analytics
```bash
cd gxa-solrcloud/bulk-analytics
kubectl create -f gxa-solrcloud-bulk-analytics-jsonl.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=1h job gxa-solrcloud-bulk-analytics-jsonl && \
kubectl create -f gxa-solrcloud-bulk-analytics-populator.yaml
```

## Single Cell Expression Atlas
