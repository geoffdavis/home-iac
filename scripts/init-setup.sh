#!/bin/bash

# Initial setup script for OpenTofu with 1Password integration
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}OpenTofu S3 Management Initial Setup${NC}"
echo "======================================"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check if mise is available and configured
if command -v mise &> /dev/null && [ -f ".mise.toml" ]; then
    echo -e "${GREEN}✓${NC} mise is installed - using mise-managed tools"
    MISE_AVAILABLE=true
    # Use mise exec to run commands through mise
    TOFU_CMD="mise exec -- tofu"
    AWS_CMD="mise exec -- aws"
    OP_CMD="mise exec -- op"
    JQ_CMD="mise exec -- jq"
    
    # Ensure mise tools are installed
    echo -e "${YELLOW}Ensuring mise tools are installed...${NC}"
    mise install
else
    echo -e "${YELLOW}!${NC} mise is not installed - checking for tools in PATH"
    MISE_AVAILABLE=false
    
    # Check OpenTofu
    if command -v tofu &> /dev/null; then
        echo -e "${GREEN}✓${NC} OpenTofu is installed"
        TOFU_CMD="tofu"
    else
        echo -e "${RED}✗${NC} OpenTofu is not installed"
        echo "Please install OpenTofu or run ./scripts/setup-mise.sh"
        exit 1
    fi
    
    AWS_CMD="aws"
    OP_CMD="op"
    JQ_CMD="jq"
fi

# Check AWS CLI
if ! $AWS_CMD --version &> /dev/null; then
    echo -e "${RED}✗${NC} AWS CLI is not installed"
    if [ "$MISE_AVAILABLE" = true ]; then
        echo "Run 'mise install' to install AWS CLI"
    else
        echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    fi
    exit 1
else
    echo -e "${GREEN}✓${NC} AWS CLI is available"
fi

# Check 1Password CLI
if ! $OP_CMD --version &> /dev/null; then
    echo -e "${RED}✗${NC} 1Password CLI is not installed"
    if [ "$MISE_AVAILABLE" = true ]; then
        echo "Run 'mise install' to install 1Password CLI"
    else
        echo "Please install 1Password CLI: https://developer.1password.com/docs/cli/get-started/"
    fi
    exit 1
else
    echo -e "${GREEN}✓${NC} 1Password CLI is available"
fi

# Check jq
if ! $JQ_CMD --version &> /dev/null; then
    echo -e "${RED}✗${NC} jq is not installed"
    if [ "$MISE_AVAILABLE" = true ]; then
        echo "Run 'mise install' to install jq"
    else
        echo "Please install jq: https://stedolan.github.io/jq/download/"
    fi
    exit 1
else
    echo -e "${GREEN}✓${NC} jq is available"
fi

# Step 1: Setup environment
echo -e "\n${YELLOW}Step 1: Setting up environment...${NC}"

if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}✓${NC} Created .env file from .env.example"
        echo -e "${YELLOW}!${NC} Please edit .env and set your OP_ACCOUNT value"
        echo "  Then run this script again."
        exit 0
    else
        echo -e "${RED}✗${NC} .env.example not found"
        exit 1
    fi
fi

# Source environment
source .env

if [ -z "${OP_ACCOUNT:-}" ]; then
    echo -e "${RED}✗${NC} OP_ACCOUNT not set in .env"
    echo "Please edit .env and set your 1Password account name"
    exit 1
fi

echo -e "${GREEN}✓${NC} Environment configured"

# Step 2: Check 1Password authentication
echo -e "\n${YELLOW}Step 2: Checking 1Password authentication...${NC}"

if ! $OP_CMD account list | grep -q "$OP_ACCOUNT"; then
    echo -e "${YELLOW}!${NC} Not signed in to 1Password. Attempting to sign in..."
    $OP_CMD signin
fi

# Test 1Password access
echo -e "Testing access to AWS credentials in 1Password..."
if $OP_CMD item get "${OP_AWS_ITEM}" --vault "${OP_AWS_VAULT}" &> /dev/null; then
    echo -e "${GREEN}✓${NC} Successfully accessed AWS credentials in 1Password"
else
    echo -e "${RED}✗${NC} Could not access '${OP_AWS_ITEM}' in ${OP_AWS_VAULT} vault"
    echo "Please ensure:"
    echo "  1. You have an item named '${OP_AWS_ITEM}' in your ${OP_AWS_VAULT} vault"
    echo "  2. The item contains your AWS Access Key ID and Secret Access Key"
    echo "  3. The field names match your .env configuration"
    exit 1
fi

# Step 3: Test AWS access
echo -e "\n${YELLOW}Step 3: Testing AWS access...${NC}"

# Export AWS credentials for testing
echo "Retrieving AWS credentials from 1Password..."

# Use environment variables for 1Password paths
if [ -n "${OP_AWS_SECTION:-}" ]; then
    # With section
    AWS_ACCESS_KEY=$($OP_CMD read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_ACCESS_KEY_FIELD}")
    AWS_SECRET_KEY=$($OP_CMD read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_SECRET_KEY_FIELD}")
else
    # Without section
    AWS_ACCESS_KEY=$($OP_CMD read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_ACCESS_KEY_FIELD}")
    AWS_SECRET_KEY=$($OP_CMD read "op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECRET_KEY_FIELD}")
fi

if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
    echo -e "${RED}✗${NC} Could not extract AWS credentials from 1Password item"
    echo "Please check:"
    echo "  1. The field names in your .env match your 1Password item"
    echo "  2. If using sections, OP_AWS_SECTION is set correctly"
    exit 1
fi

# Test AWS access
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"

if $AWS_CMD sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓${NC} AWS credentials are valid"
    ACCOUNT_ID=$($AWS_CMD sts get-caller-identity --query Account --output text)
    echo -e "  Account ID: ${BLUE}$ACCOUNT_ID${NC}"
else
    echo -e "${RED}✗${NC} AWS credentials are invalid or expired"
    exit 1
fi

# Step 4: Initialize Terraform/OpenTofu
echo -e "\n${YELLOW}Step 4: Initializing OpenTofu...${NC}"

cd environments/dev

# Initialize with local backend first
if $TOFU_CMD init; then
    echo -e "${GREEN}✓${NC} OpenTofu initialized successfully"
else
    echo -e "${RED}✗${NC} OpenTofu initialization failed"
    exit 1
fi

cd ../..

# Step 5: Run discovery script
echo -e "\n${YELLOW}Step 5: Discovering existing S3 buckets...${NC}"

if [ -x scripts/discover-s3-buckets.sh ]; then
    ./scripts/discover-s3-buckets.sh
else
    echo -e "${RED}✗${NC} Discovery script not found or not executable"
    exit 1
fi

echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "\n${BLUE}Next steps:${NC}"
echo "1. Review discovered buckets in: discovered-buckets.json"
echo "2. Create your bucket configuration:"
echo "   cp environments/dev/s3-buckets.tf.example environments/dev/s3-buckets.tf"
echo "3. Edit the configuration based on your discovered buckets"
echo "4. Run the import script that was generated:"
echo "   cd environments/dev"
echo "   ../../scripts/import-s3-buckets.sh"
echo ""
echo "For detailed instructions, see: docs/setup-guide.md"