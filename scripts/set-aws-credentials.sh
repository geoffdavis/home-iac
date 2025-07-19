#!/bin/bash
# Convenience script to set AWS credentials from 1Password
# Can be sourced or executed directly

# Function to handle script exit based on whether it's sourced or executed
safe_exit() {
    local exit_code=$1
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # Script is being sourced, use return
        return "$exit_code"
    else
        # Script is being executed, use exit
        exit "$exit_code"
    fi
}

# Find the repository root more reliably
find_repo_root() {
    local current_dir
    
    # If BASH_SOURCE is available, use it
    if [ -n "${BASH_SOURCE[0]}" ]; then
        current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    else
        # Fallback to current directory
        current_dir="$(pwd)"
    fi
    
    # Look for .env file by traversing up the directory tree
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/.env" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # If not found, check common locations
    if [ -f "$HOME/src/personal/home-iac/.env" ]; then
        echo "$HOME/src/personal/home-iac"
        return 0
    fi
    
    return 1
}

# Find repository root
REPO_ROOT=$(find_repo_root)
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Could not find repository root with .env file"
    echo "Please ensure you're in the home-iac repository"
    safe_exit 1
fi

ENV_FILE="${REPO_ROOT}/.env"

# Source environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create it from .env.example"
    safe_exit 1
fi

# Check if required variables are set
if [ -z "${OP_AWS_VAULT:-}" ] || [ -z "${OP_AWS_ITEM:-}" ] || [ -z "${OP_AWS_ACCESS_KEY_FIELD:-}" ] || [ -z "${OP_AWS_SECRET_KEY_FIELD:-}" ]; then
    echo "Error: Required environment variables not set in .env"
    echo "Please ensure the following are set:"
    echo "  - OP_AWS_VAULT"
    echo "  - OP_AWS_ITEM"
    echo "  - OP_AWS_ACCESS_KEY_FIELD"
    echo "  - OP_AWS_SECRET_KEY_FIELD"
    safe_exit 1
fi

# Build the 1Password paths
if [ -n "${OP_AWS_SECTION:-}" ]; then
    ACCESS_KEY_PATH="op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_ACCESS_KEY_FIELD}"
    SECRET_KEY_PATH="op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECTION}/${OP_AWS_SECRET_KEY_FIELD}"
else
    ACCESS_KEY_PATH="op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_ACCESS_KEY_FIELD}"
    SECRET_KEY_PATH="op://${OP_AWS_VAULT}/${OP_AWS_ITEM}/${OP_AWS_SECRET_KEY_FIELD}"
fi

# Export AWS credentials
echo "Setting AWS credentials from 1Password..."
AWS_ACCESS_KEY_ID=$(op read "$ACCESS_KEY_PATH" 2>/dev/null)
AWS_SECRET_ACCESS_KEY=$(op read "$SECRET_KEY_PATH" 2>/dev/null)
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "✓ AWS credentials set successfully"
    echo ""
    echo "You can now run OpenTofu commands:"
    echo "  cd $REPO_ROOT/environments/dev"
    echo "  tofu plan"
    echo "  tofu apply"
else
    echo "✗ Failed to retrieve AWS credentials"
    echo "Please check:"
    echo "  1. You're signed in to 1Password: op signin"
    echo "  2. Your 1Password configuration in $ENV_FILE"
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    safe_exit 1
fi