#!/bin/bash
# Script to verify existing Longhorn S3 backup permissions using credentials from 1Password

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Verifying Existing Longhorn S3 Backup Permissions${NC}"
echo "================================================="

# Source environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}✗${NC} .env file not found"
    exit 1
fi

# Check if 1Password CLI is available
if ! command -v op &> /dev/null && ! mise exec -- op --version &> /dev/null; then
    echo -e "${RED}✗${NC} 1Password CLI is not installed"
    exit 1
fi

# Use mise exec if available, otherwise use system command
if command -v mise &> /dev/null; then
    OP_CMD="mise exec -- op"
else
    OP_CMD="op"
fi

# Ensure we're signed in to the correct 1Password account
if [ -n "${OP_ACCOUNT}" ]; then
    echo "Using 1Password account: ${OP_ACCOUNT}"
    if ! $OP_CMD account list | grep -q "$OP_ACCOUNT"; then
        echo -e "${YELLOW}!${NC} Not signed in to 1Password account: ${OP_ACCOUNT}"
        echo "Attempting to sign in..."
        $OP_CMD signin --account "$OP_ACCOUNT"
    fi
fi

# Get Longhorn credentials from 1Password
echo -e "\n${YELLOW}Retrieving Longhorn credentials from 1Password...${NC}"

LONGHORN_ITEM="AWS Access Key - longhorn-s3-backup - home-ops"
LONGHORN_VAULT="${LONGHORN_VAULT:-Automation}"

# Get credentials
echo "Retrieving from: ${LONGHORN_VAULT}/${LONGHORN_ITEM}"

# Try to get the entire item first to understand its structure
if ! ITEM_JSON=$($OP_CMD item get "$LONGHORN_ITEM" --vault "$LONGHORN_VAULT" --account "${OP_ACCOUNT}" --format json 2>/dev/null); then
    echo -e "${RED}✗${NC} Could not retrieve Longhorn credentials from 1Password"
    echo "Please ensure:"
    echo "  1. You're signed in to 1Password account: ${OP_ACCOUNT}"
    echo "  2. The item exists: $LONGHORN_ITEM"
    echo "  3. It's in the vault: $LONGHORN_VAULT"
    
    # Try to list items to help debug
    echo -e "\n${YELLOW}Attempting to list items in ${LONGHORN_VAULT} vault...${NC}"
    $OP_CMD item list --vault "$LONGHORN_VAULT" --account "${OP_ACCOUNT}" 2>&1 | grep -i longhorn || echo "No items found containing 'longhorn'"
    exit 1
fi

# Extract fields from the item
# Common field names: "access key id", "access_key_id", "username", "AWS_ACCESS_KEY_ID"
ACCESS_KEY_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.label | ascii_downcase | contains("access key id") or contains("access_key_id") or contains("username")) | .value' | head -1)

# Common field names: "secret access key", "secret_access_key", "password", "AWS_SECRET_ACCESS_KEY"  
SECRET_ACCESS_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.label | ascii_downcase | contains("secret access key") or contains("secret_access_key") or contains("password")) | .value' | head -1)

# If not found in fields, check in sections
if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ]; then
    ACCESS_KEY_ID=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.id == "username" or .label == "access key id") | .value' | head -1)
    SECRET_ACCESS_KEY=$(echo "$ITEM_JSON" | jq -r '.fields[] | select(.id == "password" or .label == "secret access key") | .value' | head -1)
fi

if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}✗${NC} Could not extract AWS credentials from 1Password item"
    echo "Found fields:"
    echo "$ITEM_JSON" | jq -r '.fields[] | "\(.label): \(.id)"'
    exit 1
fi

echo -e "${GREEN}✓${NC} Retrieved Longhorn credentials from 1Password"

# Export credentials for AWS CLI
export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${AWS_REGION:-us-west-2}"

# Get current AWS identity
echo -e "\n${YELLOW}Checking AWS identity...${NC}"
if IDENTITY=$(aws sts get-caller-identity 2>/dev/null); then
    echo -e "${GREEN}✓${NC} AWS credentials are valid"
    echo -e "  User ARN: ${BLUE}$(echo $IDENTITY | jq -r '.Arn')${NC}"
    echo -e "  User ID: ${BLUE}$(echo $IDENTITY | jq -r '.UserId')${NC}"
    echo -e "  Account: ${BLUE}$(echo $IDENTITY | jq -r '.Account')${NC}"
else
    echo -e "${RED}✗${NC} AWS credentials are invalid"
    exit 1
fi

# Determine bucket name
BUCKET_NAME="longhorn-backups-home-ops"
echo -e "\n${YELLOW}Testing permissions on bucket: ${BLUE}$BUCKET_NAME${NC}"

# Test 1: List bucket (tests s3:ListBucket permission)
echo -e "\n${YELLOW}Test 1: Listing bucket contents${NC}"
if aws s3 ls "s3://${BUCKET_NAME}/" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:ListBucket permission verified"
    OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}/" --recursive | wc -l | tr -d ' ')
    echo -e "  Objects in bucket: ${BLUE}$OBJECT_COUNT${NC}"
else
    echo -e "${RED}✗${NC} Failed to list bucket (missing s3:ListBucket permission)"
    echo "  This permission is required for Longhorn to list existing backups"
fi

# Test 2: Get bucket location (tests s3:GetBucketLocation permission)
echo -e "\n${YELLOW}Test 2: Getting bucket location${NC}"
if LOCATION=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" 2>/dev/null); then
    echo -e "${GREEN}✓${NC} s3:GetBucketLocation permission verified"
    REGION=$(echo $LOCATION | jq -r '.LocationConstraint // "us-east-1"')
    echo -e "  Bucket region: ${BLUE}$REGION${NC}"
else
    echo -e "${RED}✗${NC} Failed to get bucket location (missing s3:GetBucketLocation permission)"
    echo "  This permission is required for Longhorn to determine the bucket region"
fi

# Test 3: Write object (tests s3:PutObject permission)
echo -e "\n${YELLOW}Test 3: Writing test object${NC}"
TEST_FILE="permission-test/longhorn-test-$(date +%s).txt"
if echo "Longhorn S3 permission test - $(date)" | aws s3 cp - "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:PutObject permission verified"
    echo "  Successfully wrote test file"
else
    echo -e "${RED}✗${NC} Failed to write object (missing s3:PutObject permission)"
    echo "  This permission is required for Longhorn to create backups"
fi

# Test 4: Read object (tests s3:GetObject permission)
echo -e "\n${YELLOW}Test 4: Reading test object${NC}"
if aws s3 cp "s3://${BUCKET_NAME}/${TEST_FILE}" - >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:GetObject permission verified"
    echo "  Successfully read test file"
else
    echo -e "${RED}✗${NC} Failed to read object (missing s3:GetObject permission)"
    echo "  This permission is required for Longhorn to restore from backups"
    # Try to clean up
    aws s3 rm "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1 || true
fi

# Test 5: Delete object (tests s3:DeleteObject permission)
echo -e "\n${YELLOW}Test 5: Deleting test object${NC}"
if aws s3 rm "s3://${BUCKET_NAME}/${TEST_FILE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} s3:DeleteObject permission verified"
    echo "  Successfully deleted test file"
else
    echo -e "${RED}✗${NC} Failed to delete object (missing s3:DeleteObject permission)"
    echo "  This permission is required for Longhorn to clean up old backups"
fi

# Test 6: Check versioning status and related permissions
echo -e "\n${YELLOW}Test 6: Checking bucket versioning${NC}"
if VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" 2>/dev/null); then
    VERSIONING_STATUS=$(echo "$VERSIONING" | jq -r '.Status // "Not Enabled"')
    echo -e "  Versioning: ${BLUE}$VERSIONING_STATUS${NC}"
    
    if [ "$VERSIONING_STATUS" = "Enabled" ]; then
        echo -e "${YELLOW}!${NC} Bucket versioning is enabled - testing version permissions"
        
        # Test GetObjectVersion
        if aws s3api list-object-versions --bucket "$BUCKET_NAME" --max-keys 1 >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} s3:GetObjectVersion permission verified"
        else
            echo -e "${YELLOW}!${NC} Cannot list object versions (missing s3:GetObjectVersion)"
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Cannot check versioning status"
fi

# Check for any bucket policies
echo -e "\n${YELLOW}Checking bucket policies...${NC}"
if POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null); then
    echo -e "${GREEN}✓${NC} Bucket policy exists"
    echo "  Policy summary:"
    echo "$POLICY" | jq -r '.Policy' | jq '.Statement[] | "  - \(.Sid // "Unnamed"): \(.Effect) \(.Action)"'
else
    echo -e "${YELLOW}!${NC} No bucket policy found (this is normal if using IAM user policies)"
fi

# Summary
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}       PERMISSIONS SUMMARY${NC}"
echo -e "${GREEN}=========================================${NC}"

# Count successful tests
PASSED=0
FAILED=0

echo -e "\nRequired Permissions:"
echo -n "  s3:ListBucket       - "; aws s3 ls "s3://${BUCKET_NAME}/" >/dev/null 2>&1 && { echo -e "${GREEN}✓ PASS${NC}"; ((PASSED++)); } || { echo -e "${RED}✗ FAIL${NC}"; ((FAILED++)); }
echo -n "  s3:GetBucketLocation - "; aws s3api get-bucket-location --bucket "$BUCKET_NAME" >/dev/null 2>&1 && { echo -e "${GREEN}✓ PASS${NC}"; ((PASSED++)); } || { echo -e "${RED}✗ FAIL${NC}"; ((FAILED++)); }
echo -n "  s3:GetObject        - "; [ -f "/tmp/longhorn-test-get" ] && rm /tmp/longhorn-test-get; echo "test" | aws s3 cp - "s3://${BUCKET_NAME}/permission-test/verify-get.txt" >/dev/null 2>&1 && aws s3 cp "s3://${BUCKET_NAME}/permission-test/verify-get.txt" /tmp/longhorn-test-get >/dev/null 2>&1 && { echo -e "${GREEN}✓ PASS${NC}"; ((PASSED++)); aws s3 rm "s3://${BUCKET_NAME}/permission-test/verify-get.txt" >/dev/null 2>&1; } || { echo -e "${RED}✗ FAIL${NC}"; ((FAILED++)); }
echo -n "  s3:PutObject        - "; echo "test" | aws s3 cp - "s3://${BUCKET_NAME}/permission-test/verify-put.txt" >/dev/null 2>&1 && { echo -e "${GREEN}✓ PASS${NC}"; ((PASSED++)); aws s3 rm "s3://${BUCKET_NAME}/permission-test/verify-put.txt" >/dev/null 2>&1; } || { echo -e "${RED}✗ FAIL${NC}"; ((FAILED++)); }
echo -n "  s3:DeleteObject     - "; echo "test" | aws s3 cp - "s3://${BUCKET_NAME}/permission-test/verify-del.txt" >/dev/null 2>&1 && aws s3 rm "s3://${BUCKET_NAME}/permission-test/verify-del.txt" >/dev/null 2>&1 && { echo -e "${GREEN}✓ PASS${NC}"; ((PASSED++)); } || { echo -e "${RED}✗ FAIL${NC}"; ((FAILED++)); }

echo -e "\n${YELLOW}Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All required Longhorn S3 permissions are correctly configured!${NC}"
    
    echo -e "\n${YELLOW}Longhorn Configuration:${NC}"
    echo -e "1. Backup Target URL:"
    echo -e "   ${BLUE}s3://${BUCKET_NAME}@${REGION:-$AWS_DEFAULT_REGION}/${NC}"
    echo ""
    echo -e "2. Create Kubernetes secret:"
    echo -e "   ${BLUE}kubectl create secret generic longhorn-backup-secret \\
     --from-literal=AWS_ACCESS_KEY_ID='${ACCESS_KEY_ID}' \\
     --from-literal=AWS_SECRET_ACCESS_KEY='<get-from-1password>' \\
     -n longhorn-system${NC}"
    echo ""
    echo -e "3. In Longhorn UI:"
    echo "   - Set Backup Target to the URL above"
    echo "   - Set Backup Target Credential Secret to: longhorn-backup-secret"
else
    echo -e "\n${RED}✗ Some permissions are missing!${NC}"
    echo "Please update the IAM policy for the Longhorn user to include all required permissions."
    echo "See docs/longhorn-s3-permissions.md for the complete policy."
fi

# Unset AWS credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION