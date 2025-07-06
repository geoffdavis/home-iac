#!/bin/bash
# Script to verify Longhorn S3 backup permissions

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Verifying Longhorn S3 Backup Permissions${NC}"
echo "========================================="

# Check if we're in the correct directory
if [ ! -f "Taskfile.yml" ]; then
    echo -e "${RED}✗${NC} Please run this script from the repository root directory"
    exit 1
fi

# Source environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}✗${NC} .env file not found"
    exit 1
fi

# Get the Longhorn credentials and bucket info from Terraform
echo -e "\n${YELLOW}Retrieving Longhorn S3 configuration from Terraform...${NC}"
cd environments/dev

# Check if Terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    tofu init
fi

# Get outputs
ACCESS_KEY_ID=$(tofu output -raw longhorn_backup_access_key_id 2>/dev/null || echo "")
SECRET_ACCESS_KEY=$(tofu output -raw longhorn_backup_secret_access_key 2>/dev/null || echo "")
BUCKET_NAME=$(tofu output -raw longhorn_backup_bucket_name 2>/dev/null || echo "")
BUCKET_REGION=$(tofu output -raw longhorn_backup_bucket_region 2>/dev/null || echo "us-west-2")

cd ../..

if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ] || [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}✗${NC} Could not retrieve Longhorn S3 configuration from Terraform"
    echo "  Please ensure the IAM resources have been applied:"
    echo "  cd environments/dev && tofu apply"
    exit 1
fi

echo -e "${GREEN}✓${NC} Retrieved configuration"
echo -e "  Bucket: ${BLUE}$BUCKET_NAME${NC}"
echo -e "  Region: ${BLUE}$BUCKET_REGION${NC}"

# Export credentials for AWS CLI
export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$BUCKET_REGION"

# Test 1: List bucket (tests s3:ListBucket permission)
echo -e "\n${YELLOW}Test 1: Listing bucket contents${NC}"
if aws s3 ls "s3://${BUCKET_NAME}/" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:ListBucket permission verified"
else
    echo -e "${RED}✗${NC} Failed to list bucket (missing s3:ListBucket permission)"
    exit 1
fi

# Test 2: Get bucket location (tests s3:GetBucketLocation permission)
echo -e "\n${YELLOW}Test 2: Getting bucket location${NC}"
if LOCATION=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" 2>/dev/null); then
    echo -e "${GREEN}✓${NC} s3:GetBucketLocation permission verified"
    echo -e "  Location: $(echo $LOCATION | jq -r '.LocationConstraint // "us-east-1"')"
else
    echo -e "${RED}✗${NC} Failed to get bucket location (missing s3:GetBucketLocation permission)"
    exit 1
fi

# Test 3: Write object (tests s3:PutObject permission)
echo -e "\n${YELLOW}Test 3: Writing test object${NC}"
TEST_FILE="longhorn-permission-test-$(date +%s).txt"
if echo "Longhorn S3 permission test" | aws s3 cp - "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:PutObject permission verified"
else
    echo -e "${RED}✗${NC} Failed to write object (missing s3:PutObject permission)"
    exit 1
fi

# Test 4: Read object (tests s3:GetObject permission)
echo -e "\n${YELLOW}Test 4: Reading test object${NC}"
if aws s3 cp "s3://${BUCKET_NAME}/${TEST_FILE}" - >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:GetObject permission verified"
else
    echo -e "${RED}✗${NC} Failed to read object (missing s3:GetObject permission)"
    # Try to clean up
    aws s3 rm "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1 || true
    exit 1
fi

# Test 5: Delete object (tests s3:DeleteObject permission)
echo -e "\n${YELLOW}Test 5: Deleting test object${NC}"
if aws s3 rm "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:DeleteObject permission verified"
else
    echo -e "${RED}✗${NC} Failed to delete object (missing s3:DeleteObject permission)"
    exit 1
fi

# Test 6: Check versioning status (informational)
echo -e "\n${YELLOW}Test 6: Checking bucket versioning${NC}"
VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" 2>/dev/null || echo "{}")
VERSIONING_STATUS=$(echo "$VERSIONING" | jq -r '.Status // "Not Enabled"')
echo -e "  Versioning: ${BLUE}$VERSIONING_STATUS${NC}"

if [ "$VERSIONING_STATUS" = "Enabled" ]; then
    echo -e "${YELLOW}!${NC} Bucket versioning is enabled"
    echo "  Longhorn can work with versioned buckets (s3:GetObjectVersion and s3:DeleteObjectVersion permissions included)"
fi

# Summary
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ All Longhorn S3 permissions verified!${NC}"
echo -e "${GREEN}=========================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Create Kubernetes secret with credentials:"
echo -e "   ${BLUE}kubectl create secret generic longhorn-backup-secret \\
     --from-literal=AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID \\
     --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key> \\
     -n longhorn-system${NC}"
echo ""
echo "2. Configure Longhorn backup target:"
echo -e "   ${BLUE}s3://${BUCKET_NAME}@${BUCKET_REGION}/${NC}"
echo ""
echo "3. Set the backup credential secret in Longhorn to: longhorn-backup-secret"

# Unset AWS credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION