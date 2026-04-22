#!/usr/bin/env python3
"""
One-off Solr → MongoDB copy: stream documents from Solr (cursor pagination) and
insert them into a MongoDB collection with batched insert_many.

Dependencies:
    pip install pymongo

Example:
    export SOLR_USER=solr SOLR_PASS='...'
    python3 solr_to_mongo.py \\
      --solr http://localhost:8983/solr/my-collection \\
      --mongo 'mongodb://user:pass@localhost:27017/?authSource=admin' \\
      --database mydb --collection mycoll

Large collections: use --partition-field and --max-workers (same idea as the
Helm export job) so Solr work is split by facet values.

Note: Documents are stored as returned by Solr. If Solr uses field "id" and
you want Mongo's _id to match, add --id-as-mongo-id.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import urllib.parse
import urllib.request
from base64 import b64encode
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Dict, Iterator, List, Optional, Set

try:
    from pymongo import MongoClient
    from pymongo.errors import BulkWriteError
except ImportError:
    print("Install pymongo: pip install pymongo", file=sys.stderr)
    raise SystemExit(1)


def solr_get(
    base_select_url: str,
    params: Dict[str, Any],
    auth_header: Optional[Dict[str, str]],
    timeout: int,
) -> dict:
    url = base_select_url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=auth_header or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def strip_fields(doc: dict, strip: Set[str]) -> None:
    for f in strip:
        doc.pop(f, None)


def iter_solr_partition(
    base_select_url: str,
    auth_header: Optional[Dict[str, str]],
    query: str,
    solr_batch: int,
    sort: str,
    strip: Set[str],
    timeout: int,
) -> Iterator[dict]:
    cursor = "*"
    while True:
        data = solr_get(
            base_select_url,
            {
                "q": query,
                "cursorMark": cursor,
                "sort": sort,
                "rows": solr_batch,
                "wt": "json",
            },
            auth_header,
            timeout,
        )
        docs = data["response"]["docs"]
        next_cursor = data["nextCursorMark"]
        for doc in docs:
            strip_fields(doc, strip)
            yield doc
        if next_cursor == cursor or not docs:
            break
        cursor = next_cursor


def facet_partitions(
    base_select_url: str,
    auth_header: Optional[Dict[str, str]],
    query: str,
    partition_field: str,
    timeout: int,
) -> List[str]:
    raw = solr_get(
        base_select_url,
        {
            "q": query,
            "rows": 0,
            "wt": "json",
            "facet": "true",
            f"facet.field": partition_field,
            "facet.limit": 100000,
            "facet.mincount": 1,
        },
        auth_header,
        timeout,
    )
    vals = raw["facet_counts"]["facet_fields"][partition_field]
    return vals[::2]


def main() -> None:
    ap = argparse.ArgumentParser(description="Copy Solr collection documents to MongoDB.")
    ap.add_argument(
        "--solr",
        required=True,
        help="Solr collection URL, e.g. http://host:8983/solr/mycollection",
    )
    ap.add_argument("--mongo", required=True, help="MongoDB connection URI")
    ap.add_argument("--database", required=True)
    ap.add_argument("--collection", required=True)
    ap.add_argument("--query", default="*:*", help="Solr q parameter")
    ap.add_argument(
        "--strip-fields",
        default="_version_",
        help="Comma-separated Solr fields to drop before insert (default: _version_)",
    )
    ap.add_argument(
        "--sort",
        default="id asc",
        help="Sort for cursorMark (must include uniqueKey). Default: id asc",
    )
    ap.add_argument("--solr-batch", type=int, default=5000, help="Solr rows per request")
    ap.add_argument(
        "--mongo-batch",
        type=int,
        default=2000,
        help="Documents per insert_many (default 2000)",
    )
    ap.add_argument("--timeout", type=int, default=120, help="HTTP timeout seconds")
    ap.add_argument(
        "--partition-field",
        default="",
        help="If set, discover facet values and export each partition in parallel",
    )
    ap.add_argument(
        "--max-workers",
        type=int,
        default=8,
        help="Thread pool size for partitioned mode",
    )
    ap.add_argument(
        "--drop",
        action="store_true",
        help="Drop target collection before import",
    )
    ap.add_argument(
        "--ordered-insert",
        action="store_true",
        help="Use ordered=True for insert_many (slower, stops on first error)",
    )
    ap.add_argument(
        "--id-as-mongo-id",
        default="",
        metavar="FIELD",
        help="Copy Solr FIELD to Mongo _id (e.g. id). Leave unset to keep Solr fields as-is.",
    )
    args = ap.parse_args()

    solr_base = args.solr.rstrip("/")
    select_url = solr_base + "/select" if not solr_base.endswith("/select") else solr_base

    user = os.environ.get("SOLR_USER", "")
    password = os.environ.get("SOLR_PASS", "")
    auth_header = None
    if user or password:
        auth_header = {
            "Authorization": "Basic "
            + b64encode(f"{user}:{password}".encode()).decode()
        }

    strip: Set[str] = {f.strip() for f in args.strip_fields.split(",") if f.strip()}
    id_field = args.id_as_mongo_id

    client = MongoClient(args.mongo)
    coll = client[args.database][args.collection]
    if args.drop:
        coll.drop()
        print(f"Dropped {args.database}.{args.collection}", flush=True)

    inserted_lock = threading.Lock()
    inserted_total = 0

    def prepare_doc(doc: dict) -> dict:
        if not id_field:
            return doc
        out = dict(doc)
        if id_field in out:
            out["_id"] = out[id_field]
        return out

    def flush(buffer: List[dict]) -> None:
        nonlocal inserted_total
        if not buffer:
            return
        try:
            coll.insert_many(buffer, ordered=args.ordered_insert)
        except BulkWriteError as e:
            print(e.details, file=sys.stderr)
            raise
        with inserted_lock:
            inserted_total += len(buffer)

    def pump_partition(solr_q: str, label: str) -> int:
        buf: List[dict] = []
        n = 0
        for doc in iter_solr_partition(
            select_url,
            auth_header,
            solr_q,
            args.solr_batch,
            args.sort,
            strip,
            args.timeout,
        ):
            buf.append(prepare_doc(doc))
            n += 1
            if len(buf) >= args.mongo_batch:
                flush(buf)
                buf = []
        flush(buf)
        print(f"  {label}: {n} docs", flush=True)
        return n

    if args.partition_field:
        parts = facet_partitions(
            select_url, auth_header, args.query, args.partition_field, args.timeout
        )
        print(
            f"Partition field {args.partition_field!r}: {len(parts)} values, "
            f"workers={args.max_workers}",
            flush=True,
        )

        base_q = args.query.strip()

        def partition_q(p: str) -> str:
            if base_q == "*:*":
                return f"{args.partition_field}:{p}"
            return f"({base_q}) AND ({args.partition_field}:{p})"

        def run_one(p: str) -> int:
            return pump_partition(partition_q(p), repr(p))

        with ThreadPoolExecutor(max_workers=args.max_workers) as pool:
            futures = {pool.submit(run_one, p): p for p in parts}
            for fut in as_completed(futures):
                fut.result()
        print(f"Done. insert_many total documents: {inserted_total}", flush=True)
        return

    info = solr_get(
        select_url,
        {"q": args.query, "rows": 0, "wt": "json"},
        auth_header,
        args.timeout,
    )
    num_found = info["response"]["numFound"]
    print(f"Solr reports numFound={num_found} for q={args.query!r}", flush=True)

    pump_partition(args.query, "simple")
    print(f"Done. insert_many total documents: {inserted_total}", flush=True)


if __name__ == "__main__":
    main()
