#!/bin/bash
# Run from AWS CloudShell, inside this repository. Safe to run again to ship a change.
set -euo pipefail
cd "$(dirname "$0")/.."
STACK=asktala
: "${AWS_REGION:?Open CloudShell in the region you want to use}"
MODEL_BASE_URL="${MODEL_BASE_URL:-https://api.groq.com/openai/v1}"
MODEL_NAME="${MODEL_NAME:-openai/gpt-oss-120b}"

python3 scripts/precheck.py

param_exists() { aws ssm get-parameter --name "$1" >/dev/null 2>&1; }
put_secret() { aws ssm put-parameter --name "$1" --type SecureString --value "$2" --overwrite >/dev/null; }
put_config() { aws ssm put-parameter --name "$1" --type String --value "$2" --overwrite >/dev/null; }

if ! param_exists /asktala/model/api_key; then
  read -rsp "Paste your model API key (nothing will be shown): " key; echo
  code="$(curl -s -o /tmp/models.json -w '%{http_code}' -H "Authorization: Bearer $key" "$MODEL_BASE_URL/models")"
  [ "$code" = 200 ] || { echo "The provider rejected that key (HTTP $code)."; exit 1; }
  jq -e --arg m "$MODEL_NAME" '.data[] | select(.id == $m)' /tmp/models.json >/dev/null || {
    echo "Model $MODEL_NAME is not offered. Available:"; jq -r '.data[].id' /tmp/models.json; exit 1; }
  put_secret /asktala/model/api_key "$key"
  unset key
  rm -f /tmp/models.json
  echo "Model key saved to Parameter Store."
fi
for spec in CREDS_KEY:32 CREDS_IV:16 JWT_SECRET:32 JWT_REFRESH_SECRET:32 GATEWAY_TOKEN:32; do
  name="/asktala/secrets/${spec%%:*}"
  param_exists "$name" || put_secret "$name" "$(openssl rand -hex "${spec##*:}")"
done

overrides=()
if ! aws cloudformation describe-stacks --stack-name "$STACK" >/dev/null 2>&1; then
  read -rp "Email address for alarms and budget alerts: " email
  ami="$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)"
  prefix="$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text)"
  overrides=(--parameter-overrides "AlarmEmail=$email" "AmiId=$ami" "CloudFrontPrefixListId=$prefix")
fi
aws cloudformation deploy --stack-name "$STACK" --template-file infra/stack.yaml \
  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --tags Project=SAM10 "${overrides[@]}"

output() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
bucket="$(output Bucket)"
instance="$(output InstanceId)"
put_config /asktala/config/DOMAIN "$(output DomainName)"
put_config /asktala/config/MODEL_BASE_URL "$MODEL_BASE_URL"
put_config /asktala/config/MODEL_NAME "$MODEL_NAME"
put_config /asktala/config/APP_VERSION "$(git rev-parse --short HEAD)"

aws s3 sync content "s3://$bucket/content/" --delete --exclude '*' --include '*.md'
tar -czf /tmp/app.tar.gz app/compose.yml app/compose.aws.yml app/librechat.yaml app/brand app/gateway content ops tests
aws s3 cp /tmp/app.tar.gz "s3://$bucket/release/app.tar.gz"

status="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance" --query 'InstanceInformationList[0].PingStatus' --output text)"
if [ "$status" = Online ] && [ "${1:-}" = update ]; then
  aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
    --parameters 'commands=["bash /opt/asktala/ops/update.sh"]' --query Command.CommandId --output text
fi
echo
echo "Done. App URL: $(output Url)"
echo "First start takes about 10 minutes. To ship a later change, run: scripts/deploy.sh update"
echo "Confirm the AWS Notification email that was sent to you, or alarms will not reach you."
