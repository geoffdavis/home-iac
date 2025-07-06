#!/bin/bash
# Script to update Longhorn S3 backup credentials in 1Password

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Updating Longhorn S3 Backup Credentials in 1Password${NC}"
echo "===================================================="

# Source environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}✗${NC} .env file not found"
    exit 1
fi

# Check if we're in the correct directory
if [ ! -f "Taskfile.yml" ]; then
    echo -e "${RED}✗${NC} Please run this script from the repository root directory"
    exit 1
fi

# Use mise exec if available, otherwise use system command
if command -v mise &> /dev/null; then
    OP_CMD="mise exec -- op"
else
    OP_CMD="op"
fi

# Get credentials from Terraform outputs
echo -e "\n${YELLOW}Retrieving new credentials from Terraform...${NC}"
cd environments/dev

ACCESS_KEY_ID=$(tofu output -raw longhorn_backup_access_key_id 2>/dev/null || echo "")
SECRET_ACCESS_KEY=$(tofu output -raw longhorn_backup_secret_access_key 2>/dev/null || echo "")

cd ../..

if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}✗${NC} Could not retrieve credentials from Terraform"
    exit 1
fi

echo -e "${GREEN}✓${NC} Retrieved new credentials"
echo -e "  Access Key ID: ${BLUE}$ACCESS_KEY_ID${NC}"

# 1Password item details
LONGHORN_ITEM="AWS Access Key - longhorn-s3-backup - home-ops"
LONGHORN_VAULT="${LONGHORN_VAULT:-Automation}"

# Check if the item exists
echo -e "\n${YELLOW}Checking if 1Password item exists...${NC}"
if $OP_CMD item get "$LONGHORN_ITEM" --vault "$LONGHORN_VAULT" --account "${OP_ACCOUNT}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Found existing item: $LONGHORN_ITEM"
    
    # Update the existing item
    echo -e "\n${YELLOW}Updating credentials in 1Password...${NC}"
    
    # For AWS credentials, we typically update username (access key) and password (secret key)
    if $OP_CMD item edit "$LONGHORN_ITEM" \
        --vault "$LONGHORN_VAULT" \
        --account "${OP_ACCOUNT}" \
        username="$ACCESS_KEY_ID" \
        password="$SECRET_ACCESS_KEY" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Successfully updated credentials in 1Password!"
    else
        echo -e "${RED}✗${NC} Failed to update item. You may need to update manually."
        echo ""
        echo "Manual update instructions:"
        echo "1. Open 1Password"
        echo "2. Find item: $LONGHORN_ITEM in vault: $LONGHORN_VAULT"
        echo "3. Update fields:"
        echo "   - Username/Access Key ID: $ACCESS_KEY_ID"
        echo "   - Password/Secret Access Key: $SECRET_ACCESS_KEY"
    fi
else
    echo -e "${YELLOW}!${NC} Item not found. Creating new item..."
    
    # Create new item
    if $OP_CMD item create \
        --category "API Credential" \
        --title "$LONGHORN_ITEM" \
        --vault "$LONGHORN_VAULT" \
        --account "${OP_ACCOUNT}" \
        username="$ACCESS_KEY_ID" \
        password="$SECRET_ACCESS_KEY" \
        --tags "aws,longhorn,s3,backup,kubernetes" \
        notesPlain="AWS IAM credentials for Longhorn S3 backup access. Managed by Terraform in home-iac repository." >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Successfully created new item in 1Password!"
    else
        echo -e "${RED}✗${NC} Failed to create item. Please create manually with:"
        echo "   Title: $LONGHORN_ITEM"
        echo "   Vault: $LONGHORN_VAULT"
        echo "   Username: $ACCESS_KEY_ID"
        echo "   Password: $SECRET_ACCESS_KEY"
    fi
fi

# Show next steps
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ Credentials updated in 1Password!${NC}"
echo -e "${GREEN}=========================================${NC}"

echo -e "\n${YELLOW}Next steps for Kubernetes:${NC}"
echo "1. Create the Kubernetes secret:"
echo -e "   ${BLUE}kubectl create secret generic longhorn-backup-secret \\
     --from-literal=AWS_ACCESS_KEY_ID='$ACCESS_KEY_ID' \\
     --from-literal=AWS_SECRET_ACCESS_KEY='$SECRET_ACCESS_KEY' \\
     -n longhorn-system${NC}"

echo -e "\n2. Configure Longhorn backup target:"
echo -e "   ${BLUE}s3://longhorn-backups-home-ops@us-west-2/${NC}"

echo -e "\n3. Set the backup credential secret in Longhorn to: ${BLUE}longhorn-backup-secret${NC}"