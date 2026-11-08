#!/bin/bash
# End of term: deletes everything this project created, including backups.
set -euo pipefail
STACK=asktala
read -rp "Type DELETE to remove the stack, its buckets and its parameters: " answer
[ "$answer" = DELETE ] || { echo Cancelled.; exit 1; }
output() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
for bucket in "$(output Bucket)" "$(output TrailBucket)"; do
  while :; do
    batch="$(aws s3api list-object-versions --bucket "$bucket" --max-items 500 --output json |
      jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key, VersionId}))}')"
    [ "$(jq '.Objects | length' <<<"$batch")" -eq 0 ] && break
    aws s3api delete-objects --bucket "$bucket" --delete "$batch" >/dev/null
  done
done
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
aws ssm get-parameters-by-path --path /asktala --recursive --query 'Parameters[].Name' --output text |
  tr '\t' '\n' | while read -r name; do [ -n "$name" ] && aws ssm delete-parameter --name "$name"; done
echo "Removed. Also revoke your model API key at the provider and tell your instructor."
