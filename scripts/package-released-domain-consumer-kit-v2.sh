#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 2; then
  echo "usage: package-released-domain-consumer-kit-v2.sh REPOSITORY OUTPUT_DIRECTORY" >&2
  exit 64
fi

root=$(cd "$1" && pwd)
mkdir -p "$2"
output=$(cd "$2" && pwd)
kit="$output/consumer-kit-v2"
archive="$output/gooo-interchange-consumer-kit-v2.tar.gz"
rm -rf "$kit"
mkdir -p "$kit/schemas" "$kit/scripts" "$kit/contracts" "$kit/docs"

for name in conformance evidence project relation replay resolution; do
  cp "$root/schemas/$name-v2.schema.json" "$kit/schemas/$name-v2.schema.json"
done
cp "$root/scripts/conform-released-envelope-v2.sh" "$kit/scripts/conform-released-envelope-v2.sh"
chmod 0755 "$kit/scripts/conform-released-envelope-v2.sh"
cp "$root/contracts/released-domain-envelope-denominator-v2.json" "$kit/contracts/released-domain-envelope-denominator-v2.json"
cp "$root/docs/rfcs/released-domain-envelope-v2.md" "$kit/docs/released-domain-envelope-v2.md"

target=$(jq -r '.specification.target_commit_sha' "$root/contracts/released-domain-consumer-kit-release-lock-v2.json")
jq -S -n --arg target "$target" '{
  schema:"gooo/interchange/released-domain-consumer-kit-manifest/v2",
  kit_version:"v2",
  source:{repository:"kimjooyoon/gooo-interchange-spec",tag:"v0.2.0-dev",target_commit_sha:$target},
  inventory:{files:11,checksum_entries:10,schemas:6,conformers:1,generators:0,denominators:1,documents:1},
  authority:{read_only:true,product_generation_authorized:false,repository_checkout_required:false,cross_project_required_gates:0},
  payload:[
    "contracts/released-domain-envelope-denominator-v2.json",
    "docs/released-domain-envelope-v2.md",
    "schemas/conformance-v2.schema.json",
    "schemas/evidence-v2.schema.json",
    "schemas/project-v2.schema.json",
    "schemas/relation-v2.schema.json",
    "schemas/replay-v2.schema.json",
    "schemas/resolution-v2.schema.json",
    "scripts/conform-released-envelope-v2.sh"
  ]
}' > "$kit/manifest.json"

(
  cd "$kit"
  find . -type f ! -name SHA256SUMS -printf '%P\n' | sort |
    while IFS= read -r file; do sha256sum "$file"; done > SHA256SUMS
)

rm -f "$archive"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$output" -cf - consumer-kit-v2 | gzip -n > "$archive"
