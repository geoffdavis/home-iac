# Dependency Management with mise and Renovate

This project uses **mise** (formerly rtx) for runtime version management and **Renovate** for automated dependency updates.

## mise - Runtime Version Management

mise manages tool versions for this project, ensuring consistency across development environments.

### Installation

```bash
# Run the setup script
./scripts/setup-mise.sh

# Or install manually:
# macOS
brew install mise

# Linux/macOS (alternative)
curl https://mise.run | sh
```

### Configuration

Tool versions are defined in `.mise.toml`:

```toml
[tools]
opentofu = "1.8.8"
awscli = "2.22.21"
"1password-cli" = "2.33.2"
jq = "1.7.1"
```

### Usage

Once mise is installed, tools are automatically available when you enter the project directory:

```bash
# Install all tools defined in .mise.toml
mise install

# Check installed versions
mise list

# Update a specific tool
mise install opentofu@latest

# Trust the .mise.toml file (required for auto-activation)
mise trust
```

### Shell Integration

Add to your shell configuration:

```bash
# ~/.bashrc or ~/.zshrc
eval "$(mise activate bash)"  # or zsh
```

## Renovate - Automated Dependency Updates

Renovate automatically creates pull requests to update dependencies.

### Configuration

The `renovate.json` file configures:

1. **OpenTofu Version Updates**: Monitors `versions.tf` for OpenTofu version constraints
2. **Provider Updates**: Groups Terraform provider updates together
3. **mise Tool Updates**: Updates tool versions in `.mise.toml`
4. **Schedule**: Runs weekly (before 3am on Monday, Pacific Time)

### Key Features

- **Grouped Updates**: Terraform providers are grouped to reduce PR noise
- **Auto-merge**: Patch updates for mise tools are auto-merged
- **Version Pinning**: OpenTofu versions are pinned for stability
- **Rate Limiting**: Maximum 3 concurrent PRs, 2 per hour

### Monitored Files

1. **`environments/*/versions.tf`**: OpenTofu version constraints and provider versions
2. **`.mise.toml`**: Tool versions (opentofu, awscli, 1password-cli, jq)

### Example Renovate PRs

Renovate will create PRs like:

- "Update OpenTofu to v1.8.9"
- "Update terraform-providers (aws, onepassword)"
- "Update mise tool versions"

### Customization

To add more tools or change update behavior, modify `renovate.json`:

```json
{
  "packageRules": [
    {
      "description": "Custom rule for new tool",
      "matchDepNames": ["new-tool"],
      "rangeStrategy": "auto"
    }
  ]
}
```

## Integration with Existing Scripts

The `init-setup.sh` script automatically detects and uses mise-managed tools:

```bash
# If mise is available, uses mise-managed tools
mise exec -- tofu init

# Falls back to system tools if mise is not installed
tofu init
```

## Best Practices

1. **Always use mise for local development** to ensure version consistency
2. **Review Renovate PRs** before merging, especially for major updates
3. **Test thoroughly** after updating OpenTofu or provider versions
4. **Pin versions** in production for stability

## Troubleshooting

### mise Issues

```bash
# Reset mise
rm -rf ~/.local/share/mise
mise install

# Force reinstall a tool
mise uninstall opentofu
mise install opentofu
```

### Renovate Issues

- **No PRs created**: Check if Renovate app is installed on your repository
- **Failed updates**: Review Renovate logs in PR comments
- **Rate limits**: Adjust `prConcurrentLimit` and `prHourlyLimit` in config

## CI/CD Integration

For CI/CD pipelines, you can use mise or specify versions directly:

```yaml
# GitHub Actions example
- name: Setup tools
  run: |
    curl https://mise.run | sh
    echo "$HOME/.local/bin" >> $GITHUB_PATH
    mise install
    
- name: Run OpenTofu
  run: mise exec -- tofu plan