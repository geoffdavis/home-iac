#!/bin/bash
# Script to set up DynamoDB state locking for OpenTofu

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}DynamoDB State Locking Setup${NC}"
echo "=============================="

# Source environment variables
echo -e "\n${YELLOW}Loading environment...${NC}"
if [ -f ../../.env ]; then
    source ../../.env
    echo -e "${GREEN}✓${NC} Environment loaded (OP_ACCOUNT: $OP_ACCOUNT)"
else
    echo -e "${RED}✗${NC} .env file not found"
    exit 1
fi

# Get AWS credentials from 1Password
echo -e "\n${YELLOW}Getting AWS credentials from 1Password...${NC}"
export AWS_ACCESS_KEY_ID=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_ACCESS_KEY_FIELD}")
export AWS_SECRET_ACCESS_KEY=$(op read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_SECRET_KEY_FIELD}")
echo -e "${GREEN}✓${NC} AWS credentials set"

# Check if we're in the right directory
if [[ ! "$PWD" == */environments/dev ]]; then
    echo -e "${YELLOW}Changing to environments/dev directory...${NC}"
    cd environments/dev
fi

# Step 1: Apply DynamoDB table
echo -e "\n${YELLOW}Step 1: Creating DynamoDB table...${NC}"
if tofu apply -target=aws_dynamodb_table.terraform_locks -auto-approve; then
    echo -e "${GREEN}✓${NC} DynamoDB table created successfully"
else
    echo -e "${RED}✗${NC} Failed to create DynamoDB table"
    echo -e "\n${YELLOW}Please ensure you have updated your IAM policy with the permissions from:${NC}"
    echo -e "${BLUE}docs/complete-dynamodb-permissions.json${NC}"
    exit 1
fi

# Step 2: Update backend configuration
echo -e "\n${YELLOW}Step 2: Updating backend configuration...${NC}"
sed -i.bak 's/# dynamodb_table = "opentofu-state-locks-home-iac"/dynamodb_table = "opentofu-state-locks-home-iac"/' backend.tf
echo -e "${GREEN}✓${NC} Backend configuration updated"

# Step 3: Reinitialize with locking
echo -e "\n${YELLOW}Step 3: Reinitializing OpenTofu with state locking...${NC}"
if tofu init -reconfigure; then
    echo -e "${GREEN}✓${NC} OpenTofu reinitialized with DynamoDB locking"
else
    echo -e "${RED}✗${NC} Failed to reinitialize OpenTofu"
    # Restore backup
    mv backend.tf.bak backend.tf
    exit 1
fi

# Clean up backup
rm -f backend.tf.bak

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo -e "\nDynamoDB state locking is now enabled. Your state is protected against concurrent modifications."
echo -e "\nTo use OpenTofu with credentials:"
echo -e "${BLUE}source ../../.env${NC}"
echo -e "${BLUE}export AWS_ACCESS_KEY_ID=\$(op read \"op://\${OP_AWS_VAULT}/\${OP_AWS_ITEM}/\${OP_AWS_SECTION}/\${OP_AWS_ACCESS_KEY_FIELD}\")${NC}"
echo -e "${BLUE}export AWS_SECRET_ACCESS_KEY=\$(op read \"op://\${OP_AWS_VAULT}/\${OP_AWS_ITEM}/\${OP_AWS_SECTION}/\${OP_AWS_SECRET_KEY_FIELD}\")${NC}"
echo -e "${BLUE}tofu plan${NC}"