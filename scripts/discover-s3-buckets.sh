#!/bin/bash

# Script to discover existing S3 buckets and their configurations
# This will help generate the OpenTofu configuration for importing

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}S3 Bucket Discovery Script${NC}"
echo "================================"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install it for JSON processing.${NC}"
    exit 1
fi

# Output file
OUTPUT_FILE="discovered-buckets.json"
TERRAFORM_CONFIG="environments/dev/s3-buckets.tf"

echo -e "${YELLOW}Fetching S3 buckets...${NC}"

# Get list of all buckets
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output json)

# Initialize JSON object
echo "{" > "$OUTPUT_FILE"
echo "  \"buckets\": {" >> "$OUTPUT_FILE"

FIRST=true

# Process each bucket
for bucket in $(echo "$BUCKETS" | jq -r '.[]'); do
    echo -e "\nProcessing bucket: ${GREEN}$bucket${NC}"
    
    if [ "$FIRST" = false ]; then
        echo "," >> "$OUTPUT_FILE"
    fi
    FIRST=false
    
    # Get bucket location
    LOCATION=$(aws s3api get-bucket-location --bucket "$bucket" 2>/dev/null | jq -r '.LocationConstraint // "us-east-1"')
    if [ "$LOCATION" = "null" ]; then
        LOCATION="us-east-1"
    fi
    
    # Get bucket ACL
    ACL=$(aws s3api get-bucket-acl --bucket "$bucket" 2>/dev/null || echo '{"Grants":[]}')
    
    # Check if bucket has canned ACL
    CANNED_ACL="private"
    if echo "$ACL" | jq -e '.Grants | length > 1' > /dev/null; then
        CANNED_ACL="custom"
    fi
    
    # Get versioning status
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$bucket" 2>/dev/null || echo '{}')
    VERSIONING_STATUS=$(echo "$VERSIONING" | jq -r '.Status // "Disabled"')
    VERSIONING_ENABLED=false
    if [ "$VERSIONING_STATUS" = "Enabled" ]; then
        VERSIONING_ENABLED=true
    fi
    
    # Get encryption configuration
    ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$bucket" 2>/dev/null || echo 'null')
    
    # Get public access block configuration
    PUBLIC_ACCESS=$(aws s3api get-bucket-public-access-block --bucket "$bucket" 2>/dev/null || echo 'null')
    
    # Get lifecycle configuration
    LIFECYCLE=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" 2>/dev/null || echo 'null')
    
    # Get bucket policy
    POLICY=$(aws s3api get-bucket-policy --bucket "$bucket" 2>/dev/null || echo 'null')
    
    # Get bucket tags
    TAGS=$(aws s3api get-bucket-tagging --bucket "$bucket" 2>/dev/null || echo 'null')
    
    # Write to output file
    echo -n "    \"${bucket//[^a-zA-Z0-9_]/_}\": {" >> "$OUTPUT_FILE"
    echo -n "\"bucket_name\": \"$bucket\"" >> "$OUTPUT_FILE"
    echo -n ", \"region\": \"$LOCATION\"" >> "$OUTPUT_FILE"
    
    if [ "$CANNED_ACL" != "private" ]; then
        echo -n ", \"acl\": \"$CANNED_ACL\"" >> "$OUTPUT_FILE"
    fi
    
    if [ "$VERSIONING_ENABLED" = true ]; then
        echo -n ", \"versioning\": true" >> "$OUTPUT_FILE"
    fi
    
    if [ "$ENCRYPTION" != "null" ]; then
        echo -n ", \"encryption\": $ENCRYPTION" >> "$OUTPUT_FILE"
    fi
    
    if [ "$PUBLIC_ACCESS" != "null" ]; then
        echo -n ", \"public_access_block\": $PUBLIC_ACCESS" >> "$OUTPUT_FILE"
    fi
    
    if [ "$LIFECYCLE" != "null" ]; then
        echo -n ", \"lifecycle\": $LIFECYCLE" >> "$OUTPUT_FILE"
    fi
    
    if [ "$POLICY" != "null" ]; then
        echo -n ", \"policy\": $POLICY" >> "$OUTPUT_FILE"
    fi
    
    if [ "$TAGS" != "null" ]; then
        echo -n ", \"tags\": $TAGS" >> "$OUTPUT_FILE"
    fi
    
    echo -n "}" >> "$OUTPUT_FILE"
done

echo "" >> "$OUTPUT_FILE"
echo "  }" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

echo -e "\n${GREEN}Discovery complete!${NC}"
echo -e "Results saved to: ${YELLOW}$OUTPUT_FILE${NC}"

# Generate Terraform import commands
echo -e "\n${GREEN}Generating import commands...${NC}"
IMPORT_FILE="scripts/import-s3-buckets.sh"

echo "#!/bin/bash" > "$IMPORT_FILE"
echo "# Auto-generated script to import S3 buckets into OpenTofu state" >> "$IMPORT_FILE"
echo "" >> "$IMPORT_FILE"
echo "cd environments/dev" >> "$IMPORT_FILE"
echo "" >> "$IMPORT_FILE"

for bucket in $(echo "$BUCKETS" | jq -r '.[]'); do
    BUCKET_KEY="${bucket//[^a-zA-Z0-9_]/_}"
    echo "echo \"Importing bucket: $bucket\"" >> "$IMPORT_FILE"
    echo "tofu import 'module.s3_buckets.aws_s3_bucket.this[\"$BUCKET_KEY\"]' '$bucket'" >> "$IMPORT_FILE"
    echo "" >> "$IMPORT_FILE"
done

chmod +x "$IMPORT_FILE"

echo -e "Import script saved to: ${YELLOW}$IMPORT_FILE${NC}"
echo -e "\n${GREEN}Next steps:${NC}"
echo "1. Review the discovered configuration in $OUTPUT_FILE"
echo "2. Update environments/dev/main.tf with the bucket configurations"
echo "3. Run 'tofu init' in environments/dev/"
echo "4. Run the import script: $IMPORT_FILE"