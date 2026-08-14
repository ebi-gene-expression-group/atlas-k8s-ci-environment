#!/bin/bash
# Rsync one GXA env data dir (solr_data or zk_data) between environments on Isilon.
# Copies CONTENTS of SRC/DIR/ into DST/DIR/ (trailing slashes on both paths).
#
# Submit (Codon / Slurm), e.g. staging -> public:
#   sbatch --partition=datamover --job-name=gxa-rsync-solr \
#     --export=ALL,DIR=solr_data,SRC=staging,DST=public \
#     scripts/slurm/rsync-gxa-env-data.sbatch
#   sbatch --partition=datamover --job-name=gxa-rsync-zk \
#     --export=ALL,DIR=zk_data,SRC=staging,DST=public \
#     scripts/slurm/rsync-gxa-env-data.sbatch
#
# Or one-liners with --wrap (contents copy: trailing slashes on both paths):
#   sbatch --partition=datamover --time=24:00:00 --mem=4G \
#     --job-name=gxa-rsync-solr_data --output=gxa-rsync-solr_data.%j.out \
#     --wrap='rsync -a --delete --info=progress2 --stats \
#       /nfs/public/rw/fg/atlas/gxa/environments/staging/solr_data/ \
#       /nfs/public/rw/fg/atlas/gxa/environments/public/solr_data/'
#   sbatch --partition=datamover --time=02:00:00 --mem=4G \
#     --job-name=gxa-rsync-zk_data --output=gxa-rsync-zk_data.%j.out \
#     --wrap='rsync -a --delete --info=progress2 --stats \
#       /nfs/public/rw/fg/atlas/gxa/environments/staging/zk_data/ \
#       /nfs/public/rw/fg/atlas/gxa/environments/public/zk_data/'
#
# Optional overrides: BASE, SRC, DST, DIR
#
#SBATCH --partition=datamover
#SBATCH --output=gxa-rsync-%x-%j.out
#SBATCH --error=gxa-rsync-%x-%j.err
#SBATCH --time=48:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
# Optional:
##SBATCH --account=YOUR_ACCOUNT

set -euo pipefail

BASE="${BASE:-/nfs/public/rw/fg/atlas/gxa/environments}"
SRC="${SRC:-staging}"
DST="${DST:-public}"
DIR="${DIR:?Set DIR=solr_data or DIR=zk_data (e.g. sbatch --export=ALL,DIR=solr_data,...)}"

case "$DIR" in
  solr_data|zk_data) ;;
  *)
    echo "DIR must be solr_data or zk_data (got: $DIR)" >&2
    exit 1
    ;;
esac

src_path="$BASE/$SRC/$DIR"
dst_path="$BASE/$DST/$DIR"

if [[ ! -d "$src_path" ]]; then
  echo "Source missing: $src_path" >&2
  exit 1
fi

mkdir -p "$BASE/$DST" "$dst_path"

echo "=== rsync $DIR: $SRC -> $DST (contents of ${DIR}/) ==="
echo "host=$(hostname)  start=$(date -Is)"
echo "src=${src_path}/"
echo "dst=${dst_path}/"
printf '%12s %5s %12s %10s  %s\n' BYTES PCT RATE ETA 'XFR / CHECK'

# Trailing slashes: copy contents into dst dir (not nest DIR/DIR).
rsync -a --delete --info=progress2 --stats \
  "${src_path}/" \
  "${dst_path}/"

echo
echo "=== done $DIR ==="
echo "end=$(date -Is)"
du -sh "$dst_path"
