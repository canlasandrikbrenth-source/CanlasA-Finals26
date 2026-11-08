#!/bin/bash
# Dumps the database to S3. Runs from a timer; the log line records how it was started.
set -euo pipefail
# shellcheck disable=SC1091
source /etc/asktala.env
trigger=manual
[ -n "${INVOCATION_ID:-}" ] && trigger=systemd-timer
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
key="backups/mongo/asktala-$stamp.archive.gz"
say() { echo "$(date -u +%FT%TZ) backup trigger=$trigger $*"; }

if docker exec asktala-mongo mongodump --quiet --archive --gzip --db AskTala |
  aws s3 cp --region "$AWS_REGION" - "s3://$BUCKET/$key"; then
  bytes="$(aws s3api head-object --region "$AWS_REGION" --bucket "$BUCKET" --key "$key" --query ContentLength --output text)"
  if [ "$bytes" -gt 0 ]; then
    aws cloudwatch put-metric-data --region "$AWS_REGION" --namespace AskTala --metric-name BackupSuccess --value 1
    say "status=ok key=$key bytes=$bytes"
    exit 0
  fi
fi
say "status=failed key=$key"
exit 1
