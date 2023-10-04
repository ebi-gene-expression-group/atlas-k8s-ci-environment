# atlas-k8s-ci-environment
Collection of Kubernetes manifests for CI of Expression Atlas web applications


## Before We Start: Populated Read-Only Volumes
In order to run tests on multiple branches concurrently we need to set up read-only volumes. The pattern we follow to
populate them with data is described in the following document:
https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/readonlymany-disks

This can be generalised to vendors other than Google Cloud Platform. However, the first step requires creating a
snapshot class with a **`driver` which is platform-specific**. In the remainder of this document this snapshot class 
will be used to create snapshots of read-write volumes.For GCP this is in the top-level directory of this repo:
```bash
kubectl create -f snapshot-class.yaml
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
