#!/usr/bin/env python3
"""
Universal Credential Management CLI
Manages AWS IAM credentials with automatic rotation and 1Password storage
"""

import sys
import argparse
from pathlib import Path

# Add the lib directory to the Python path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from credential_manager import (
    CredentialManager, 
    TerraformCredentialProvider, 
    OnePasswordStorage,
    load_environment,
    check_prerequisites,
    Colors
)
from service_configs import get_service_config, list_available_services


def print_colored(message: str, color: str = Colors.NC) -> None:
    """Print a colored message to stdout"""
    print(f"{color}{message}{Colors.NC}")


def main():
    """Main CLI function"""
    parser = argparse.ArgumentParser(
        description="Update AWS IAM credentials in 1Password",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s postgresql          # Update PostgreSQL backup credentials
  %(prog)s longhorn           # Update Longhorn backup credentials
  %(prog)s --list             # List available services
  
Available services:
  """ + "\n  ".join(f"- {service}" for service in list_available_services())
    )
    
    parser.add_argument(
        "service",
        nargs="?",
        help="Service name to update credentials for"
    )
    
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available services"
    )
    
    parser.add_argument(
        "--terraform-dir",
        default="environments/dev",
        help="Terraform directory (default: environments/dev)"
    )
    
    args = parser.parse_args()
    
    # Handle list command
    if args.list:
        print("Available services:")
        for service in list_available_services():
            print(f"  - {service}")
        return 0
    
    # Validate service argument
    if not args.service:
        parser.error("Service name is required (use --list to see available services)")
    
    try:
        # Check prerequisites
        check_prerequisites()
        
        # Load environment
        env_vars = load_environment()
        op_account = env_vars.get('OP_ACCOUNT')
        if not op_account:
            print_colored(
                "✗ OP_ACCOUNT environment variable not found in .env", 
                Colors.RED
            )
            return 1
        
        # Get service configuration
        try:
            config = get_service_config(args.service)
        except ValueError as e:
            print_colored(f"✗ {e}", Colors.RED)
            return 1
        
        # Initialize components
        provider = TerraformCredentialProvider(args.terraform_dir)
        storage = OnePasswordStorage(op_account)
        manager = CredentialManager(provider, storage)
        
        # Update credentials
        success = manager.update_credentials(config)
        
        return 0 if success else 1
        
    except FileNotFoundError as e:
        print_colored(f"✗ {e}", Colors.RED)
        return 1
    except RuntimeError as e:
        print_colored(f"✗ {e}", Colors.RED)
        return 1
    except KeyboardInterrupt:
        print_colored("\n✗ Operation cancelled by user", Colors.RED)
        return 1
    except Exception as e:
        print_colored(f"✗ Unexpected error: {e}", Colors.RED)
        return 1


if __name__ == "__main__":
    sys.exit(main())