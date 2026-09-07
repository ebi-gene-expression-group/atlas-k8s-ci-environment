# Slurm helpers for GXA Isilon env data

## Rsync env data

Script: [`rsync-gxa-env-data.sbatch`](rsync-gxa-env-data.sbatch)

Copies **contents** (trailing slashes). `DIR` empty = whole env directory;
`DIR=solr_data` or `DIR=zk_data` = that subdirectory only.

### Fallback: HL2 `/nfs/public` → EBI `/nfs/ebi/public`

```bash
cd /path/to/atlas-k8s-ci-environment

sbatch --job-name=gxa-rsync-fallback \
  --export=ALL,SRC_BASE=/nfs/public/rw/fg/atlas/gxa/environments,DST_BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments,SRC=fallback,DST=fallback \
  scripts/slurm/rsync-gxa-env-data.sbatch
```

Equivalent `--wrap`:

```bash
sbatch --partition=datamover --time=48:00:00 --mem=8G \
  --job-name=gxa-rsync-fallback \
  --output=gxa-rsync-fallback.%j.out \
  --wrap='mkdir -p /nfs/ebi/public/rw/fg/atlas/gxa/environments/fallback &&
    rsync -a --delete --info=progress2 --stats \
      /nfs/public/rw/fg/atlas/gxa/environments/fallback/ \
      /nfs/ebi/public/rw/fg/atlas/gxa/environments/fallback/'
```

Directory names are both `fallback`, but the copied `zk_data` still uses **staging** pod/FQDN names (`gxa-staging-solrcloud-zookeeper-*`). Rewrite before deploying SolrCloud on cluster 121:

```bash
BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments SRC=staging DST=fallback \
  ./scripts/slurm/rewrite-gxa-zk-env-names.sh
```

### Same-base staging → public (`sbatch --wrap`)

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

### Same-base via the `.sbatch` script

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

After a **same-base staging → public** copy, stop destination ZK/Solr, then rewrite names:

```bash
SRC=staging DST=public ./scripts/slurm/rewrite-gxa-zk-env-names.sh
```

Then redeploy SolrCloud. Script: [`rewrite-gxa-zk-env-names.sh`](rewrite-gxa-zk-env-names.sh).
