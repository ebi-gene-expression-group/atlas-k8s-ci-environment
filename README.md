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
