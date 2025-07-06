#!/bin/bash
# Convenience script to set AWS credentials from 1Password

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create it from .env.example"
    exit 1
fi

# Check if required variables are set
if [ -z "${OP_AWS_VAULT:-}" ] || [ -z "${OP_AWS_ITEM:-}" ] || [ -z "${OP_AWS_ACCESS_KEY_FIELD:-}" ] || [ -z "${OP_AWS_SECRET_KEY_FIELD:-}" ]; then
    echo "Error: Required environment variables not set in .env"
    echo "Please ensure the following are set:"
    echo "  - OP_AWS_VAULT"
    echo "  - OP_AWS_ITEM"
    echo "  - OP_AWS_ACCESS_KEY_FIELD"
    echo "  - OP_AWS_SECRET_KEY_FIELD"
    exit 1
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
export AWS_ACCESS_KEY_ID=$(op read "$ACCESS_KEY_PATH")
export AWS_SECRET_ACCESS_KEY=$(op read "$SECRET_KEY_PATH")

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "✓ AWS credentials set successfully"
    echo ""
    echo "You can now run OpenTofu commands:"
    echo "  tofu plan"
    echo "  tofu apply"
else
    echo "✗ Failed to retrieve AWS credentials"
    echo "Please check your 1Password configuration in .env"
    exit 1
fi