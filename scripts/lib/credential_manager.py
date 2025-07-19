#!/usr/bin/env python3
"""
Modular Credential Management Framework
Handles AWS IAM credential rotation and 1Password storage
"""

import os
import sys
import subprocess
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from abc import ABC, abstractmethod


class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


@dataclass
class CredentialConfig:
    """Configuration for a credential set"""
    service_name: str
    terraform_output_prefix: str
    onepassword_item_title: str
    onepassword_vault: str
    tags: List[str]
    description: str
    s3_bucket_name: Optional[str] = None
    aws_region: str = "us-west-2"


@dataclass
class AWSCredentials:
    """AWS credential pair"""
    access_key_id: str
    secret_access_key: str


class CredentialProvider(ABC):
    """Abstract base class for credential providers"""
    
    @abstractmethod
    def get_credentials(self, config: CredentialConfig) -> AWSCredentials:
        """Retrieve credentials from the provider"""
        pass


class TerraformCredentialProvider(CredentialProvider):
    """Retrieves credentials from Terraform outputs"""
    
    def __init__(self, terraform_dir: str = "environments/dev"):
        self.terraform_dir = terraform_dir
    
    def get_credentials(self, config: CredentialConfig) -> AWSCredentials:
        """Retrieve credentials from Terraform outputs"""
        original_dir = os.getcwd()
        try:
            os.chdir(self.terraform_dir)
            
            # Get access key ID
            access_key_cmd = [
                "bash", "-c",
                f"source ../../scripts/set-aws-credentials.sh && "
                f"export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY && "
                f"mise exec -- tofu output -raw "
                f"{config.terraform_output_prefix}_access_key_id"
            ]
            result = self._run_command(access_key_cmd)
            access_key_id = result.stdout.strip()
            
            # Get secret access key
            secret_key_cmd = [
                "bash", "-c",
                f"source ../../scripts/set-aws-credentials.sh && "
                f"export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY && "
                f"mise exec -- tofu output -raw "
                f"{config.terraform_output_prefix}_secret_access_key"
            ]
            result = self._run_command(secret_key_cmd)
            secret_access_key = result.stdout.strip()
            
            if not access_key_id or not secret_access_key:
                raise ValueError("Empty credentials returned from Terraform")
                
            return AWSCredentials(access_key_id, secret_access_key)
            
        finally:
            os.chdir(original_dir)
    
    def _run_command(self, cmd: List[str]) -> subprocess.CompletedProcess:
        """Run a command and return the result"""
        try:
            return subprocess.run(
                cmd, capture_output=True, text=True, check=True
            )
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{e.stderr}")


class OnePasswordStorage:
    """Handles 1Password credential storage"""
    
    def __init__(self, account: str):
        self.account = account
        self.op_cmd = self._get_op_command()
    
    def _get_op_command(self) -> List[str]:
        """Get the appropriate 1Password CLI command"""
        try:
            subprocess.run(
                ["mise", "--version"], 
                capture_output=True, check=True
            )
            return ["mise", "exec", "--", "op"]
        except (subprocess.CalledProcessError, FileNotFoundError):
            return ["op"]
    
    def item_exists(self, item_title: str, vault: str) -> bool:
        """Check if a 1Password item exists"""
        try:
            subprocess.run(
                self.op_cmd + [
                    "item", "get", item_title,
                    "--vault", vault,
                    "--account", self.account
                ],
                capture_output=True, check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False
    
    def create_item(self, config: CredentialConfig, 
                   credentials: AWSCredentials) -> bool:
        """Create new 1Password item"""
        try:
            subprocess.run(
                self.op_cmd + [
                    "item", "create",
                    "--category", "API Credential",
                    "--title", config.onepassword_item_title,
                    "--vault", config.onepassword_vault,
                    "--account", self.account,
                    f"username={credentials.access_key_id}",
                    f"password={credentials.secret_access_key}",
                    "--tags", ",".join(config.tags),
                    f"notesPlain={config.description}"
                ],
                capture_output=True, check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False
    
    def update_item(self, config: CredentialConfig, 
                   credentials: AWSCredentials) -> bool:
        """Update existing 1Password item"""
        try:
            subprocess.run(
                self.op_cmd + [
                    "item", "edit", config.onepassword_item_title,
                    "--vault", config.onepassword_vault,
                    "--account", self.account,
                    f"username={credentials.access_key_id}",
                    f"password={credentials.secret_access_key}"
                ],
                capture_output=True, check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False


class CredentialManager:
    """Main credential management orchestrator"""
    
    def __init__(self, provider: CredentialProvider, 
                 storage: OnePasswordStorage):
        self.provider = provider
        self.storage = storage
    
    def print_colored(self, message: str, color: str = Colors.NC) -> None:
        """Print a colored message to stdout"""
        print(f"{color}{message}{Colors.NC}")
    
    def update_credentials(self, config: CredentialConfig) -> bool:
        """Update credentials for a service"""
        self.print_colored(
            f"Updating {config.service_name} Credentials in 1Password", 
            Colors.BLUE
        )
        print("=" * (len(config.service_name) + 40))
        
        # Get credentials from provider
        self.print_colored(
            "\nRetrieving new credentials...", Colors.YELLOW
        )
        
        try:
            credentials = self.provider.get_credentials(config)
        except Exception as e:
            self.print_colored(f"✗ Failed to retrieve credentials: {e}", 
                             Colors.RED)
            return False
        
        self.print_colored("✓ Retrieved new credentials", Colors.GREEN)
        self.print_colored(
            f"  Access Key ID: {credentials.access_key_id}", Colors.BLUE
        )
        
        # Store in 1Password
        self.print_colored(
            "\nChecking if 1Password item exists...", Colors.YELLOW
        )
        
        if self.storage.item_exists(config.onepassword_item_title, 
                                  config.onepassword_vault):
            self.print_colored(
                f"✓ Found existing item: {config.onepassword_item_title}", 
                Colors.GREEN
            )
            
            self.print_colored(
                "\nUpdating credentials in 1Password...", Colors.YELLOW
            )
            
            if self.storage.update_item(config, credentials):
                self.print_colored(
                    "✓ Successfully updated credentials in 1Password!", 
                    Colors.GREEN
                )
            else:
                self.print_colored(
                    "✗ Failed to update item. Manual update required.", 
                    Colors.RED
                )
                self._print_manual_instructions(config, credentials)
                return False
        else:
            self.print_colored(
                "! Item not found. Creating new item...", Colors.YELLOW
            )
            
            if self.storage.create_item(config, credentials):
                self.print_colored(
                    "✓ Successfully created new item in 1Password!", 
                    Colors.GREEN
                )
            else:
                self.print_colored(
                    "✗ Failed to create item. Manual creation required.", 
                    Colors.RED
                )
                self._print_manual_instructions(config, credentials)
                return False
        
        # Show success and next steps
        self._print_success_message(config, credentials)
        return True
    
    def _print_manual_instructions(self, config: CredentialConfig, 
                                 credentials: AWSCredentials) -> None:
        """Print manual update instructions"""
        print("\nManual update instructions:")
        print("1. Open 1Password")
        print(f"2. Find/Create item: {config.onepassword_item_title}")
        print(f"   in vault: {config.onepassword_vault}")
        print("3. Update fields:")
        print(f"   - Username: {credentials.access_key_id}")
        print("   - Password: [REDACTED]")
    
    def _print_success_message(self, config: CredentialConfig, 
                             credentials: AWSCredentials) -> None:
        """Print success message and next steps"""
        self.print_colored(
            "\n" + "=" * 44, Colors.GREEN
        )
        self.print_colored(
            "✓ Credentials updated in 1Password!", Colors.GREEN
        )
        self.print_colored(
            "=" * 44, Colors.GREEN
        )
        
        self.print_colored(
            f"\nNext steps for {config.service_name}:", Colors.YELLOW
        )
        print("1. Retrieve credentials from 1Password when configuring")
        
        if config.s3_bucket_name:
            print("2. Use the following S3 bucket:")
            self.print_colored(f"   {config.s3_bucket_name}", Colors.BLUE)
            
            print("\n3. Example environment variables:")
            self.print_colored(
                f"   export AWS_ACCESS_KEY_ID='{credentials.access_key_id}'", 
                Colors.BLUE
            )
            self.print_colored(
                "   export AWS_SECRET_ACCESS_KEY='[From 1Password]'", 
                Colors.BLUE
            )
            self.print_colored(
                f"   export S3_BUCKET='{config.s3_bucket_name}'", 
                Colors.BLUE
            )
            self.print_colored(
                f"   export AWS_REGION='{config.aws_region}'", Colors.BLUE
            )


def load_environment() -> Dict[str, str]:
    """Load environment variables from .env file"""
    env_file = Path(".env")
    if not env_file.exists():
        raise FileNotFoundError(".env file not found")
    
    env_vars = {}
    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                env_vars[key.strip()] = value.strip().strip('"\'')
    
    return env_vars


def check_prerequisites() -> None:
    """Check if we're in the correct directory"""
    if not Path("Taskfile.yml").exists():
        raise RuntimeError(
            "Please run this script from the repository root directory"
        )