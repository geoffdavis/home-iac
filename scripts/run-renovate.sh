#!/bin/bash
# Script to run Renovate locally with GitHub token from 1Password

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running Renovate locally${NC}"
echo "========================="

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

# Get GitHub token from 1Password
echo -e "${YELLOW}Retrieving GitHub token from 1Password...${NC}"

# You'll need to configure these variables in your .env file
GITHUB_TOKEN_VAULT="${GITHUB_TOKEN_VAULT:-Private}"
GITHUB_TOKEN_ITEM="${GITHUB_TOKEN_ITEM:-GitHub Personal Access Token}"
GITHUB_TOKEN_FIELD="${GITHUB_TOKEN_FIELD:-token}"

# Retrieve the token
GITHUB_TOKEN=$($OP_CMD read "op://${GITHUB_TOKEN_VAULT}/${GITHUB_TOKEN_ITEM}/${GITHUB_TOKEN_FIELD}" 2>/dev/null)

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}✗${NC} Could not retrieve GitHub token from 1Password"
    echo "Please ensure you have:"
    echo "  1. A GitHub personal access token in 1Password"
    echo "  2. The following variables set in .env:"
    echo "     GITHUB_TOKEN_VAULT (default: Private)"
    echo "     GITHUB_TOKEN_ITEM (default: GitHub Personal Access Token)"
    echo "     GITHUB_TOKEN_FIELD (default: token)"
    exit 1
fi

echo -e "${GREEN}✓${NC} GitHub token retrieved successfully"

# Get repository info
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ $REPO_URL =~ github\.com[:/]([^/]+)/([^/\.]+)(\.git)?$ ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
    REPO="${REPO_OWNER}/${REPO_NAME}"
else
    echo -e "${RED}✗${NC} Could not determine GitHub repository from git remote"
    exit 1
fi

echo -e "${YELLOW}Repository:${NC} $REPO"

# Run Renovate
echo -e "\n${YELLOW}Running Renovate...${NC}"

# Create a minimal config for CLI execution if needed
cat > renovate-cli.json << EOF
{
  "platform": "github",
  "token": "$GITHUB_TOKEN",
  "repositories": ["$REPO"],
  "extends": ["config:base"]
}
EOF

# Use npx to run Renovate without installing globally
export RENOVATE_TOKEN="$GITHUB_TOKEN"
export LOG_LEVEL="${LOG_LEVEL:-info}"

echo -e "${YELLOW}Executing Renovate for ${REPO}...${NC}\n"

# Use mise exec if available, otherwise use system npx
if command -v mise &> /dev/null; then
    NPX_CMD="mise exec -- npx"
else
    NPX_CMD="npx"
fi

# Run renovate with the repository as a positional argument
$NPX_CMD --yes renovate \
  --platform=github \
  --token="$GITHUB_TOKEN" \
  --dry-run="${DRY_RUN:-false}" \
  --require-config \
  "$REPO"

# Clean up
rm -f renovate-cli.json

echo -e "\n${GREEN}✓ Renovate run completed!${NC}"
echo -e "${YELLOW}Note:${NC} Use DRY_RUN=true to run in dry-run mode"
echo -e "${YELLOW}Note:${NC} Use LOG_LEVEL=debug for more detailed output"