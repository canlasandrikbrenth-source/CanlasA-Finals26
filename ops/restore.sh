#!/bin/bash
# Restores the database from a dump in S3 and prints the time taken.
# Usage: restore.sh            restores the newest dump
#        restore.sh <s3-key>   restores that dump
set -euo pipefail
# shellcheck disable=SC1091
source /etc/asktala.env
key="${1:-$(aws s3 ls --region "$AWS_REGION" "s3://$BUCKET/backups/mongo/" | sort | tail -1 | awk '{print "backups/mongo/"$4}')}"
[ -n "$key" ] && [ "$key" != "backups/mongo/" ] || { echo "No backup found."; exit 1; }

counts() {
  docker exec asktala-mongo mongosh --quiet AskTala --eval \
    'print("users=" + db.users.countDocuments() + " conversations=" + db.conversations.countDocuments() + " messages=" + db.messages.countDocuments())'
}

echo "This replaces the live database with: $key"
read -r -p 'Type RESTORE to continue: ' answer
[ "$answer" = RESTORE ] || { echo Cancelled.; exit 1; }

started="$(date +%s)"
echo "start: $(date -u +%FT%TZ)"
echo "before: $(counts)"
safety="backups/mongo/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).archive.gz"
docker exec asktala-mongo mongodump --quiet --archive --gzip --db AskTala |
  aws s3 cp --region "$AWS_REGION" - "s3://$BUCKET/$safety"
echo "safety copy: $safety"

docker stop asktala-app
aws s3 cp --region "$AWS_REGION" "s3://$BUCKET/$key" - |
  docker exec -i asktala-mongo mongorestore --quiet --archive --gzip --drop
docker start asktala-app
until curl -fs http://127.0.0.1:3080/health >/dev/null; do sleep 2; done

echo "after: $(counts)"
echo "end: $(date -u +%FT%TZ)"
echo "elapsed_seconds: $(( $(date +%s) - started ))"
