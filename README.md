# K8S Configuration for Atlas Apps

This repo contains k8s files for Gene Expressions Atlas and Single Cell Expression Atlas on k8s.

## Helm Chart Structure

This repository uses Helm to manage Kubernetes manifests for the GXA and SCXA applications, with a shared chart for bioentity-properties.

### Structure

```
charts/
  gxa/                  # Helm chart for GXA
  scxa/                 # Helm chart for SCXA
  bioentity-properties/ # Shared Helm chart for both apps
```

### Usage

To install the GXA chart (which depends on bioentity-properties):

```sh
cd charts/gxa
helm dependency update
helm install gxa .
```

To install the SCXA chart:

```sh
cd charts/scxa
helm dependency update
helm install scxa .
```

You can customize deployments by editing the respective `values.yaml` files.

TODO
- [ ] move gxa items into the gxa chart
- [ ] move bioentity items
- [ ] move scxa items into the scxa chart
- [ ] move solr items into their own chart

