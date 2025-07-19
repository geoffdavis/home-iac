#!/usr/bin/env python3
"""
Script to update PostgreSQL S3 backup credentials in 1Password
"""

import os
import sys
import subprocess
import json
from pathlib import Path
from typing import Optional, Tuple


class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


def print_colored(message: str, color: str = Colors.NC) -> None:
    """Print a colored message to stdout"""
    print(f"{color}{message}{Colors.NC}")


def run_command(cmd: list, capture_output: bool = True, check: bool = True) -> subprocess.CompletedProcess:
    """Run a command and return the result"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            check=check
        )
        return result
    except subprocess.CalledProcessError as e:
        if capture_output:
            print_colored(f"✗ Command failed: {' '.join(cmd)}", Colors.RED)
            if e.stderr:
                print_colored(f"Error: {e.stderr.strip()}", Colors.RED)
        raise


def load_environment() -> dict:
    """Load environment variables from .env file"""
    env_file = Path(".env")
    if not env_file.exists():
        print_colored("✗ .env file not found", Colors.RED)
        sys.exit(1)
    
    env_vars = {}
    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                env_vars[key.strip()] = value.strip().strip('"\'')
    
    return env_vars


def check_prerequisites() -> None:
    """Check if we're in the correct directory and have required tools"""
    if not Path("Taskfile.yml").exists():
        print_colored("✗ Please run this script from the repository root directory", Colors.RED)
        sys.exit(1)


def get_op_command() -> list:
    """Get the appropriate 1Password CLI command"""
    try:
        # Check if mise is available
        run_command(["mise", "--version"], capture_output=True)
        return ["mise", "exec", "--", "op"]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ["op"]


def get_terraform_credentials() -> Tuple[str, str]:
    """Retrieve credentials from Terraform outputs"""
    print_colored("\nRetrieving new credentials from Terraform...", Colors.YELLOW)
    
    original_dir = os.getcwd()
    try:
        os.chdir("environments/dev")
        
        # Set up AWS credentials first
        run_command(["bash", "-c", "source ../../scripts/set-aws-credentials.sh && export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"], capture_output=False)
        
        # Get access key ID using mise exec
        result = run_command(["bash", "-c", "source ../../scripts/set-aws-credentials.sh && export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY && mise exec -- tofu output -raw postgresql_backup_access_key_id"])
        access_key_id = result.stdout.strip()
        
        # Get secret access key using mise exec
        result = run_command(["bash", "-c", "source ../../scripts/set-aws-credentials.sh && export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY && mise exec -- tofu output -raw postgresql_backup_secret_access_key"])
        secret_access_key = result.stdout.strip()
        
        if not access_key_id or not secret_access_key:
            raise ValueError("Empty credentials returned from Terraform")
            
        return access_key_id, secret_access_key
        
    except subprocess.CalledProcessError:
        print_colored("✗ Could not retrieve credentials from Terraform", Colors.RED)
        sys.exit(1)
    finally:
        os.chdir(original_dir)


def check_1password_item_exists(op_cmd: list, item_name: str, vault: str, account: str) -> bool:
    """Check if a 1Password item exists"""
    try:
        run_command(op_cmd + ["item", "get", item_name, "--vault", vault, "--account", account])
        return True
    except subprocess.CalledProcessError:
        return False


def update_1password_item(op_cmd: list, item_name: str, vault: str, account: str, 
                         access_key_id: str, secret_access_key: str) -> bool:
    """Update existing 1Password item"""
    try:
        run_command(op_cmd + [
            "item", "edit", item_name,
            "--vault", vault,
            "--account", account,
            f"username={access_key_id}",
            f"password={secret_access_key}"
        ])
        return True
    except subprocess.CalledProcessError:
        return False


def create_1password_item(op_cmd: list, item_name: str, vault: str, account: str,
                         access_key_id: str, secret_access_key: str) -> bool:
    """Create new 1Password item"""
    try:
        run_command(op_cmd + [
            "item", "create",
            "--category", "API Credential",
            "--title", item_name,
            "--vault", vault,
            "--account", account,
            f"username={access_key_id}",
            f"password={secret_access_key}",
            "--tags", "aws,postgresql,s3,backup,database",
            "notesPlain=AWS IAM credentials for PostgreSQL S3 backup access. Managed by Terraform in home-iac repository."
        ])
        return True
    except subprocess.CalledProcessError:
        return False


def main():
    """Main function"""
    print_colored("Updating PostgreSQL S3 Backup Credentials in 1Password", Colors.BLUE)
    print("=======================================================")
    
    # Check prerequisites
    check_prerequisites()
    
    # Load environment variables
    env_vars = load_environment()
    
    # Get required environment variables
    op_account = env_vars.get('OP_ACCOUNT')
    if not op_account:
        print_colored("✗ OP_ACCOUNT environment variable not found in .env", Colors.RED)
        sys.exit(1)
    
    # Get 1Password command
    op_cmd = get_op_command()
    
    # Get credentials from Terraform
    access_key_id, secret_access_key = get_terraform_credentials()
    
    print_colored("✓ Retrieved new credentials", Colors.GREEN)
    print_colored(f"  Access Key ID: {access_key_id}", Colors.BLUE)
    
    # 1Password item details
    item_name = "AWS Access Key - postgresql-s3-backup - home-ops"
    vault = env_vars.get('POSTGRESQL_VAULT', 'Automation')
    
    # Check if item exists
    print_colored("\nChecking if 1Password item exists...", Colors.YELLOW)
    
    if check_1password_item_exists(op_cmd, item_name, vault, op_account):
        print_colored(f"✓ Found existing item: {item_name}", Colors.GREEN)
        
        # Update existing item
        print_colored("\nUpdating credentials in 1Password...", Colors.YELLOW)
        
        if update_1password_item(op_cmd, item_name, vault, op_account, access_key_id, secret_access_key):
            print_colored("✓ Successfully updated credentials in 1Password!", Colors.GREEN)
        else:
            print_colored("✗ Failed to update item. You may need to update manually.", Colors.RED)
            print("\nManual update instructions:")
            print("1. Open 1Password")
            print(f"2. Find item: {item_name} in vault: {vault}")
            print("3. Update fields:")
            print(f"   - Username/Access Key ID: {access_key_id}")
            print("   - Password/Secret Access Key: [REDACTED]")
            sys.exit(1)
    else:
        print_colored("! Item not found. Creating new item...", Colors.YELLOW)
        
        if create_1password_item(op_cmd, item_name, vault, op_account, access_key_id, secret_access_key):
            print_colored("✓ Successfully created new item in 1Password!", Colors.GREEN)
        else:
            print_colored("✗ Failed to create item. Please create manually with:", Colors.RED)
            print(f"   Title: {item_name}")
            print(f"   Vault: {vault}")
            print(f"   Username: {access_key_id}")
            print("   Password: [REDACTED]")
            sys.exit(1)
    
    # Show next steps
    print_colored("\n============================================", Colors.GREEN)
    print_colored("✓ Credentials updated in 1Password!", Colors.GREEN)
    print_colored("============================================", Colors.GREEN)
    
    print_colored("\nNext steps for PostgreSQL backup:", Colors.YELLOW)
    print("1. Retrieve credentials from 1Password when configuring backup scripts")
    print("2. Use the following S3 bucket for backups:")
    print_colored("   postgresql-backup-home-ops", Colors.BLUE)
    
    print("\n3. Example environment variables for backup scripts:")
    print_colored(f"   export AWS_ACCESS_KEY_ID='{access_key_id}'", Colors.BLUE)
    print_colored("   export AWS_SECRET_ACCESS_KEY='[Retrieved from 1Password]'", Colors.BLUE)
    print_colored("   export S3_BUCKET='postgresql-backup-home-ops'", Colors.BLUE)
    print_colored("   export AWS_REGION='us-west-2'", Colors.BLUE)


if __name__ == "__main__":
    main()