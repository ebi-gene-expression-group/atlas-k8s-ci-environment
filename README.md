# atlas-k8s-ci-environment
Collection of Kubernetes manifests for CI of Expression Atlas web applications


## Before We Start
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
```bash
cd gxa-data
kubectl create -f gxa-data-rwo-pvc.yaml && \
kubectl create -f gxa-data-populator-job.yaml && \
kubectl -n jenkins-gene-expression wait --for=condition=complete --timeout=12h job gxa-data-populator && \
kubectl create -f gxa-data-rwo-snapshot.yaml && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot gxa-data-rwo-snapshot && \
kubectl -n jenkins-gene-expression wait --for=jsonpath='{status.readyToUse}'=true --timeout=15m volumesnapshot gxa-data-ontology-rwo-snapshot && \
kubectl create -f gxa-data-rox-pvc.yaml
```

# PostgreSQL

# Solr


## Single Cell Expression Atlas
