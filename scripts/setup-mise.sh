#!/bin/bash
# Script to set up mise for dependency management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up mise for dependency management...${NC}"

# Check if mise is installed
if ! command -v mise &> /dev/null; then
    echo -e "${YELLOW}mise is not installed. Installing...${NC}"
    
    # Detect OS and install mise
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install mise
        else
            curl https://mise.run | sh
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl https://mise.run | sh
    else
        echo -e "${RED}Unsupported OS. Please install mise manually from https://mise.jdx.dev${NC}"
        exit 1
    fi
    
    # Add mise to shell
    echo -e "${YELLOW}Adding mise to your shell...${NC}"
    echo 'eval "$(mise activate bash)"' >> ~/.bashrc
    echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
    
    echo -e "${GREEN}mise installed! Please restart your shell or run: eval \"\$(mise activate bash)\"${NC}"
fi

# Install tools defined in .mise.toml
echo -e "${GREEN}Installing tools defined in .mise.toml...${NC}"
mise install

# Verify installations
echo -e "${GREEN}Verifying tool installations:${NC}"
mise list

# Set up local environment
echo -e "${GREEN}Setting up mise environment...${NC}"
mise trust

echo -e "${GREEN}✓ mise setup complete!${NC}"
echo -e "${YELLOW}Tools installed:${NC}"
echo "  - opentofu: $(mise exec -- tofu version 2>/dev/null | head -1 || echo 'not available')"
echo "  - aws-cli: $(mise exec -- aws --version 2>/dev/null || echo 'not available')"
echo "  - 1password-cli: $(mise exec -- op --version 2>/dev/null || echo 'not available')"
echo "  - jq: $(mise exec -- jq --version 2>/dev/null || echo 'not available')"

echo -e "\n${GREEN}All tools are managed by mise and will be automatically installed/updated.${NC}"