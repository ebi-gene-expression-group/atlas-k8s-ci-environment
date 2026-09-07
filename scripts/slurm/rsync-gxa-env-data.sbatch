#!/bin/bash
# Rsync GXA env data on Isilon (Codon / Slurm datamover).
# Copies CONTENTS (trailing slashes). Same-host env copy, or Hinxton → EBI.
#
# Fallback Solr/ZK (Hinxton public → EBI public, whole env tree):
#   sbatch --partition=datamover --job-name=gxa-rsync-fallback \
#     --export=ALL,SRC_BASE=/nfs/public/rw/fg/atlas/gxa/environments,DST_BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments,SRC=fallback,DST=fallback \
#     scripts/slurm/rsync-gxa-env-data.sbatch
#
# One dir only: add DIR=solr_data or DIR=zk_data to --export.
#
# Same-base staging → public:
#   sbatch --partition=datamover --job-name=gxa-rsync-solr \
#     --export=ALL,DIR=solr_data,SRC=staging,DST=public \
#     scripts/slurm/rsync-gxa-env-data.sbatch
#
# Optional overrides: SRC_BASE, DST_BASE, BASE, SRC, DST, DIR
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
SRC_BASE="${SRC_BASE:-$BASE}"
DST_BASE="${DST_BASE:-$SRC_BASE}"
SRC="${SRC:-staging}"
DST="${DST:-public}"
DIR="${DIR:-}"

if [[ -n "$DIR" ]]; then
  case "$DIR" in
    solr_data|zk_data) ;;
    *)
      echo "DIR must be solr_data, zk_data, or empty for the whole env (got: $DIR)" >&2
      exit 1
      ;;
  esac
  src_path="$SRC_BASE/$SRC/$DIR"
  dst_path="$DST_BASE/$DST/$DIR"
else
  src_path="$SRC_BASE/$SRC"
  dst_path="$DST_BASE/$DST"
fi

if [[ ! -d "$src_path" ]]; then
  echo "Source missing: $src_path" >&2
  exit 1
fi

mkdir -p "$dst_path"

echo "=== rsync ${DIR:-<env>}: $src_path -> $dst_path ==="
echo "host=$(hostname)  start=$(date -Is)"
echo "src=${src_path}/"
echo "dst=${dst_path}/"
printf '%12s %5s %12s %10s  %s\n' BYTES PCT RATE ETA 'XFR / CHECK'

# Trailing slashes: copy contents into dst dir (not nest DIR/DIR).
rsync -a --delete --info=progress2 --stats \
  "${src_path}/" \
  "${dst_path}/"

echo
echo "=== done ${DIR:-$DST} ==="
echo "end=$(date -Is)"
du -sh "$dst_path"
