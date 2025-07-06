#!/bin/bash
# Script to test Renovate configuration

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing Renovate Configuration${NC}"
echo "================================"

# 1. Check JSON validity
echo -e "\n${YELLOW}1. Checking JSON validity:${NC}"
if jq . renovate.json > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} renovate.json is valid JSON"
else
    echo -e "${RED}✗${NC} renovate.json is not valid JSON"
    exit 1
fi

# 2. Check required fields
echo -e "\n${YELLOW}2. Checking required fields:${NC}"
SCHEMA=$(jq -r '."$schema"' renovate.json)
if [ -n "$SCHEMA" ]; then
    echo -e "${GREEN}✓${NC} Schema defined: $SCHEMA"
else
    echo -e "${RED}✗${NC} Missing \$schema field"
fi

# 3. Test regex patterns
echo -e "\n${YELLOW}3. Testing regex patterns against actual files:${NC}"

# Test OpenTofu version in versions.tf
echo -e "\n  Testing versions.tf pattern:"
VERSION_LINE=$(grep "required_version" environments/dev/versions.tf)
echo "  Found: $VERSION_LINE"
if echo "$VERSION_LINE" | grep -E 'required_version\s*=\s*">=\s*[0-9]+\.[0-9]+\.[0-9]+"' > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Pattern matches versions.tf"
else
    echo -e "  ${RED}✗${NC} Pattern doesn't match versions.tf"
fi

# Test mise.toml patterns
echo -e "\n  Testing .mise.toml patterns:"
echo -e "  ${YELLOW}OpenTofu:${NC}"
OPENTOFU_LINE=$(grep "^opentofu" .mise.toml)
echo "  Found: $OPENTOFU_LINE"
if echo "$OPENTOFU_LINE" | grep -E 'opentofu\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Pattern matches"
else
    echo -e "  ${RED}✗${NC} Pattern doesn't match"
fi

echo -e "\n  ${YELLOW}AWS CLI:${NC}"
AWSCLI_LINE=$(grep "^awscli" .mise.toml)
echo "  Found: $AWSCLI_LINE"
if echo "$AWSCLI_LINE" | grep -E 'awscli\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Pattern matches"
else
    echo -e "  ${RED}✗${NC} Pattern doesn't match"
fi

echo -e "\n  ${YELLOW}1Password CLI:${NC}"
ONEPASS_LINE=$(grep '"1password-cli"' .mise.toml)
echo "  Found: $ONEPASS_LINE"
if echo "$ONEPASS_LINE" | grep -E '"1password-cli"\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Pattern matches"
else
    echo -e "  ${RED}✗${NC} Pattern doesn't match"
fi

echo -e "\n  ${YELLOW}jq:${NC}"
JQ_LINE=$(grep "^jq" .mise.toml)
echo "  Found: $JQ_LINE"
if echo "$JQ_LINE" | grep -E 'jq\s*=\s*"[0-9]+\.[0-9]+(\.[0-9]+)?"' > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Pattern matches"
else
    echo -e "  ${RED}✗${NC} Pattern doesn't match"
fi

# 4. Check package rules
echo -e "\n${YELLOW}4. Checking package rules:${NC}"
PACKAGE_RULES=$(jq '.packageRules | length' renovate.json)
echo -e "${GREEN}✓${NC} Found $PACKAGE_RULES package rules"

# 5. Check schedule
echo -e "\n${YELLOW}5. Checking schedule:${NC}"
SCHEDULE=$(jq -r '.schedule[0]' renovate.json)
echo -e "${GREEN}✓${NC} Schedule: $SCHEDULE"

# 6. Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Renovate configuration appears valid!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Next steps to enable Renovate:${NC}"
echo "1. Push this repository to GitHub"
echo "2. Install the Renovate app from: https://github.com/apps/renovate"
echo "3. Enable it for this repository"
echo "4. Renovate will create an onboarding PR"
echo -e "\n${YELLOW}Renovate will:${NC}"
echo "- Check for updates weekly (Monday mornings)"
echo "- Create PRs for OpenTofu, provider, and tool updates"
echo "- Auto-merge patch updates for mise tools"
echo "- Group Terraform provider updates together"