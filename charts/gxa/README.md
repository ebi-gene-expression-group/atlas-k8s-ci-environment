# GXA chart

Deployment

```bash
helm upgrade \
  --reuse-values gxa-test \
  -f values.yaml \
  --set tomcat.deployerPassword=tomcat  \
  --set secrets.solr.password=.. \
  --set secrets.solr.username=.. \
  --set secrets.jdbc.password=.. \
  --set secrets.jdbc.username=.. \
  .
```