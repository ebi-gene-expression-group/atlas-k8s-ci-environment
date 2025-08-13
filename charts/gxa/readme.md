TODO

- [x] create gxa chart based on tomcat image
- [x] mount nfs files
- [x] run tomcat pod with tc_fg02 user
- [ ] create pvc & pv for webapps and conf/Catalina directories persistency, replace emptyDir volumes
- [ ] put war into tomcat. 3 options are
    - [ ] 1. copy the war to the pod using an initContainer or a sidecar container
    - [ ] 2. bake war into docker image - requires a new build process for this dockerfile
    - [x] 3. deploy the war using tomcat manager - requires changeing the webapps into a pv (currently it is an ephemeral emptyDir)
- [ ] enable k8s probes for tomcat (they are currently disabled in deployment.yaml)
- [x] create bioentity volume
- [ ] postgres populator job
- [ ] solr populator job
