#!/usr/bin/env bash
# After rsync of zk_data from SRC→DST, rename pod-folder links and rewrite
# ZooKeeper dynamic-config FQDNs so the copy matches the destination release.
#
# Example (Codon, public copy of staging):
#   SRC=staging DST=public ./scripts/slurm/rewrite-gxa-zk-env-names.sh
#
# Stop ZK (and Solr) in the destination env first so nothing rewrites NFS.
# Does not touch SRC. Only edits DST/zk_data.
set -euo pipefail

BASE="${BASE:-/nfs/public/rw/fg/atlas/gxa/environments}"
SRC="${SRC:-staging}"
DST="${DST:-public}"
REPLICAS="${REPLICAS:-3}"

src_token="gxa-${SRC}-solrcloud"
dst_token="gxa-${DST}-solrcloud"
zk="${BASE}/${DST}/zk_data"

if [[ ! -d "$zk" ]]; then
  echo "Missing zk_data dir: $zk" >&2
  exit 1
fi

echo "=== rewrite ZK env names: $SRC -> $DST ==="
echo "zk=$zk"
echo "token ${src_token} -> ${dst_token}"

cd "$zk"

for i in $(seq 0 $((REPLICAS - 1))); do
  src_link="${src_token}-zookeeper-${i}"
  dst_link="${dst_token}-zookeeper-${i}"
  if [[ ! -e "$src_link" && ! -e "$dst_link" ]]; then
    echo "ERROR: neither $src_link nor $dst_link exists" >&2
    ls -la >&2 || true
    exit 1
  fi
  if [[ -L "$src_link" || -e "$src_link" ]]; then
    tgt=$(readlink "$src_link" 2>/dev/null || echo "")
    if [[ -z "$tgt" ]]; then
      # Real directory named for SRC — leave it; still need a DST name.
      tgt="$src_link"
    fi
    if [[ -e "$dst_link" && ! -L "$dst_link" ]]; then
      echo "Removing blocking directory $dst_link (fresh empty ZK dir)"
      rm -rf "$dst_link"
    fi
    ln -sfn "$tgt" "$dst_link"
    echo "link $dst_link -> $tgt"
  fi
done

# Text configs only. Do not sed binary version-2 txn logs / snapshots.
changed=0
found=0
while IFS= read -r f; do
  found=$((found + 1))
  if grep -q -- "$src_token" "$f"; then
    # GNU sed (Codon) and BSD sed both accept -i.bak
    sed -i.bak "s/${src_token}/${dst_token}/g" "$f"
    rm -f "${f}.bak"
    changed=$((changed + 1))
    echo "rewrote $f"
  fi
done < <(find "$zk" \( -name 'zoo.cfg.dynamic' -o -name 'zoo.cfg.dynamic.*' -o -name 'zoo.cfg' \) -type f | sort)
if [[ "$found" -eq 0 ]]; then
  echo "ERROR: no zoo.cfg.dynamic files under $zk" >&2
  exit 1
fi
echo "rewrote $changed config file(s)"

echo
echo "=== remaining $src_token in zoo.cfg* (should be empty) ==="
grep -R -- "$src_token" --include='zoo.cfg*' "$zk" || echo "(none)"

echo
echo "=== DST links ==="
ls -la "${dst_token}"-zookeeper-* 2>/dev/null || true

echo
echo "=== sample zoo.cfg.dynamic ==="
find "$zk" -name 'zoo.cfg.dynamic' -exec echo "-- {} --" \; -exec cat {} \;
