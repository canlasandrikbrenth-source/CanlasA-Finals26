#!/bin/bash
# Fetches settings from Parameter Store into memory-only storage and starts the system.
set -euo pipefail
set -a
# shellcheck disable=SC1091
source /etc/asktala.env
set +a

runtime=/run/asktala
mkdir -p "$runtime"
chmod 700 "$runtime"
env_file="$runtime/app.env"
umask 077
: >"$env_file"
for path in /asktala/secrets /asktala/config; do
  aws ssm get-parameters-by-path --region "$AWS_REGION" --path "$path" --with-decryption \
    --query 'Parameters[].[Name,Value]' --output text |
    while IFS=$'\t' read -r name value; do
      printf '%s=%s\n' "${name##*/}" "$value" >>"$env_file"
    done
done
domain="$(sed -n 's/^DOMAIN=//p' "$env_file")"
{
  echo "DOMAIN_CLIENT=https://$domain"
  echo "DOMAIN_SERVER=https://$domain"
  echo "ALLOW_REGISTRATION=false"
} >>"$env_file"

export ENV_FILE="$env_file"
primary=registry.librechat.ai/librechat-ai/librechat:v0.8.8
fallback=ghcr.io/danny-avila/librechat:v0.8.8
if docker pull "$primary"; then
  export BASE_IMAGE="$primary"
else
  docker pull "$fallback"
  export BASE_IMAGE="$fallback"
fi

cd /opt/asktala/app
docker compose --env-file "$env_file" -f compose.yml -f compose.aws.yml up -d --build --remove-orphans
