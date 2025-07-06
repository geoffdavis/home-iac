#!/bin/bash
# Wrapper script to set AWS credentials and run the import

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up AWS credentials from 1Password...${NC}"

# Source environment if not already loaded
if [ -z "${OP_AWS_VAULT:-}" ]; then
    if [ -f /Users/gadavis/src/personal/home-iac/.env ]; then
        source /Users/gadavis/src/personal/home-iac/.env
    else
        echo -e "${RED}✗${NC} .env file not found or variables not set"
        exit 1
    fi
fi

# Get AWS credentials from 1Password using environment variables
AWS_ACCESS_KEY_ID=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_ACCESS_KEY_FIELD}")
AWS_SECRET_ACCESS_KEY=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_SECRET_KEY_FIELD}")

# Export AWS credentials
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

echo -e "${GREEN}✓${NC} AWS credentials set"

# Check if we're already in environments/dev
if [[ "$PWD" == */environments/dev ]]; then
    echo "Already in environments/dev directory"
else
    cd environments/dev
fi

echo -e "\n${YELLOW}Importing S3 buckets...${NC}"

# Import each bucket
echo -e "\nImporting bucket: ${GREEN}home-assistant-backups-hassio-pi${NC}"
tofu import 'module.s3_buckets.aws_s3_bucket.this["home_assistant_backups_hassio_pi"]' 'home-assistant-backups-hassio-pi'

echo -e "\nImporting bucket: ${GREEN}longhorn-backups-home-ops${NC}"
tofu import 'module.s3_buckets.aws_s3_bucket.this["longhorn_backups_home_ops"]' 'longhorn-backups-home-ops'

# Import related resources
echo -e "\n${YELLOW}Importing related resources...${NC}"

# Import ACLs
echo -e "Importing ACL for home-assistant-backups-hassio-pi"
tofu import 'module.s3_buckets.aws_s3_bucket_acl.this["home_assistant_backups_hassio_pi"]' 'home-assistant-backups-hassio-pi,private' || true

echo -e "Importing ACL for longhorn-backups-home-ops"
tofu import 'module.s3_buckets.aws_s3_bucket_acl.this["longhorn_backups_home_ops"]' 'longhorn-backups-home-ops,private' || true

# Import encryption configurations
echo -e "Importing encryption for home-assistant-backups-hassio-pi"
tofu import 'module.s3_buckets.aws_s3_bucket_server_side_encryption_configuration.this["home_assistant_backups_hassio_pi"]' 'home-assistant-backups-hassio-pi' || true

echo -e "Importing encryption for longhorn-backups-home-ops"
tofu import 'module.s3_buckets.aws_s3_bucket_server_side_encryption_configuration.this["longhorn_backups_home_ops"]' 'longhorn-backups-home-ops' || true

# Import public access blocks
echo -e "Importing public access block for home-assistant-backups-hassio-pi"
tofu import 'module.s3_buckets.aws_s3_bucket_public_access_block.this["home_assistant_backups_hassio_pi"]' 'home-assistant-backups-hassio-pi' || true

echo -e "Importing public access block for longhorn-backups-home-ops"
tofu import 'module.s3_buckets.aws_s3_bucket_public_access_block.this["longhorn_backups_home_ops"]' 'longhorn-backups-home-ops' || true

echo -e "\n${GREEN}Import complete!${NC}"
echo -e "\nRun 'tofu plan' to verify the imported configuration."