#!/bin/bash
# Applies the release most recently uploaded to S3.
set -euo pipefail
# shellcheck disable=SC1091
source /etc/asktala.env
aws s3 cp --region "$AWS_REGION" "s3://$BUCKET/release/app.tar.gz" /tmp/app.tar.gz
tar -xzf /tmp/app.tar.gz -C /opt/asktala
bash /opt/asktala/ops/install.sh
