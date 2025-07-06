# 1Password Integration Setup Guide

This guide explains how to set up 1Password CLI and integrate it with OpenTofu for secure AWS credentials management.

## Prerequisites

1. 1Password account with CLI access
2. AWS credentials stored in 1Password

## Installation

### 1. Install 1Password CLI

**macOS:**
```bash
brew install --cask 1password-cli
```

**Linux:**
```bash
# Download from https://app-updates.agilebits.com/product_history/CLI2
curl -sSfL https://downloads.1password.com/linux/cli/stable/op_linux_amd64_v2.24.0.tar.gz | tar -xz
sudo mv op /usr/local/bin/
```

### 2. Sign in to 1Password CLI

```bash
# Sign in with your 1Password account
op account add

# Or if already added, sign in
op signin
```

### 3. Configure Environment

Create or update your `.env` file:

```bash
# 1Password Account Configuration
export OP_ACCOUNT="your-account-name"

# Optional: Set session token for automation
# export OP_SESSION_youraccountname="your-session-token"
```

## AWS Credentials in 1Password

Your AWS credentials should be stored in 1Password with the following structure:

**Vault:** Private  
**Item Title:** AWS Access Key - S3 - Personal  
**Fields:**
- Access Key ID (in the first field)
- Secret Access Key (in the second field)

### Creating the 1Password Item

1. Open 1Password
2. Create a new "Login" or "API Credential" item
3. Set the title to "AWS Access Key - S3 - Personal"
4. Add your AWS Access Key ID as the first field
5. Add your AWS Secret Access Key as the second field
6. Save in the "Private" vault

## Testing the Integration

1. Source your environment file:
   ```bash
   source .env
   ```

2. Test 1Password CLI:
   ```bash
   op item get "AWS Access Key - S3 - Personal" --vault Private
   ```

3. Initialize OpenTofu:
   ```bash
   cd environments/dev
   tofu init
   ```

## Troubleshooting

### Issue: 1Password provider not authenticating
- Ensure you're signed in: `op signin`
- Check your OP_ACCOUNT environment variable
- Verify the item exists in the correct vault

### Issue: AWS credentials not found
- Verify the item title matches exactly: "AWS Access Key - S3 - Personal"
- Check the vault name is "Private"
- Ensure fields are in the correct order (Access Key ID first, Secret Key second)

## Security Best Practices

1. Never commit AWS credentials to Git
2. Use separate AWS IAM users with minimal required permissions
3. Rotate credentials regularly
4. Use 1Password's session timeout features
5. Consider using AWS IAM roles when possible

## Alternative Field Structure

If your 1Password item has a different structure, update the data source in `main.tf`:

```hcl
# For items with named fields
data "onepassword_item" "aws_credentials" {
  vault = "Private"
  title = "AWS Access Key - S3 - Personal"
}

# Then reference fields by name:
# access_key = data.onepassword_item.aws_credentials.field["access_key_id"]
# secret_key = data.onepassword_item.aws_credentials.field["secret_access_key"]