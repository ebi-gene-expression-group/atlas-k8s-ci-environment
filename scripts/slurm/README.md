# Slurm helpers for GXA Isilon env data

## Rsync `solr_data` / `zk_data` between environments

Script: [`rsync-gxa-env-data.sbatch`](rsync-gxa-env-data.sbatch)

Copies **contents** of `…/<src>/<dir>/` into `…/<dst>/<dir>/` (trailing slashes).

### Preferred: two `sbatch --wrap` jobs on `datamover`

```bash
sbatch --partition=datamover --time=24:00:00 --mem=4G \
  --job-name=gxa-rsync-solr_data \
  --output=gxa-rsync-solr_data.%j.out \
  --wrap='rsync -a --delete --info=progress2 --stats \
    /nfs/public/rw/fg/atlas/gxa/environments/staging/solr_data/ \
    /nfs/public/rw/fg/atlas/gxa/environments/public/solr_data/'

sbatch --partition=datamover --time=02:00:00 --mem=4G \
  --job-name=gxa-rsync-zk_data \
  --output=gxa-rsync-zk_data.%j.out \
  --wrap='rsync -a --delete --info=progress2 --stats \
    /nfs/public/rw/fg/atlas/gxa/environments/staging/zk_data/ \
    /nfs/public/rw/fg/atlas/gxa/environments/public/zk_data/'
```

### Or via the `.sbatch` script

```bash
cd /path/to/atlas-k8s-ci-environment

sbatch --job-name=gxa-rsync-solr \
  --export=ALL,DIR=solr_data,SRC=staging,DST=public \
  scripts/slurm/rsync-gxa-env-data.sbatch

sbatch --job-name=gxa-rsync-zk \
  --export=ALL,DIR=zk_data,SRC=staging,DST=public \
  scripts/slurm/rsync-gxa-env-data.sbatch
```

Progress uses `--info=progress2` (overall %, not per-file).

After both finish: create `gxa-public-*` symlinks and rewrite `zoo.cfg.dynamic*` hostnames before redeploying SolrCloud.
