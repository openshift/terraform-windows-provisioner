# Contributing to BYOH Provisioner

Thank you for your interest in contributing to the BYOH Provisioner project! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Environment details**: OS, Terraform version, platform (AWS/Azure/GCP/etc.)
- **Logs or error messages** (sanitize any sensitive information)
- **Screenshots** if applicable

### Suggesting Enhancements

We welcome feature requests! Please create an issue with:

- **Clear description** of the proposed feature
- **Use case**: Why is this feature needed?
- **Proposed implementation** (if you have ideas)
- **Alternatives considered**

### Pull Requests

1. **Fork the repository** and create your branch from `main`.
2. **Make your changes**:
   - Follow the coding standards (see below).
   - Add or update tests as needed.
   - Update documentation as needed.
3. **Test your changes**:
   - Test on at least one cloud platform.
   - Ensure existing functionality still works.
   - Run shellcheck on bash scripts.
4. **Commit your changes**:
   - Use clear, descriptive commit messages.
   - Reference any related issues.
5. **Push to your fork** and submit a pull request.

## Development Setup

### Prerequisites

- Bash 4.0+
- Terraform >= 1.0.0
- OpenShift/Kubernetes cluster access
- ShellCheck (for linting)

### Local Development

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/terraform-windows-provisioner.git
cd terraform-windows-provisioner

# Create a feature branch
git checkout -b feature/my-new-feature

# Make changes and test
./byoh.sh help

# Lint bash scripts
shellcheck byoh.sh lib/*.sh
```

### Testing

Before submitting a PR:

1. **Manual Testing**:
   ```bash
   # Test on your platform
   ./byoh.sh apply test 1
   ./byoh.sh destroy test 1
   ```

2. **Validation**:
   ```bash
   # Check bash syntax
   bash -n byoh.sh
   bash -n lib/*.sh

   # Run shellcheck
   shellcheck byoh.sh lib/*.sh
   ```

3. **Terraform Validation**:
   ```bash
   cd aws/  # or azure/, gcp/, etc.
   terraform fmt -check
   terraform validate
   ```

## Coding Standards

### Bash Scripts

- Use `set -euo pipefail` at the beginning.
- Use `shellcheck` and address all warnings.
- Use meaningful variable names.
- Add comments for complex logic.
- Use functions for reusable code.
- Handle errors gracefully with informative messages.
- Use `local` for function variables.
- Quote variables: `"${variable}"`.

### Terraform

- Use `terraform fmt` for formatting.
- Use meaningful resource names.
- Add descriptions to all variables.
- Mark sensitive variables appropriately.
- Use consistent naming conventions.
- Add comments for complex configurations.

### Documentation

- Keep README.md up to date.
- Document all configuration variables.
- Provide examples for common use cases.
- Update CHANGELOG.md for notable changes.

## Project Structure

```
terraform-windows-provisioner/
├── byoh.sh                 # Main entry point
├── lib/                    # Modular libraries
│   ├── config.sh          # Configuration management
│   ├── credentials.sh     # Credential handling
│   ├── platform.sh        # Platform-specific logic
│   ├── terraform.sh       # Terraform operations
│   └── validation.sh      # Input validation
├── configs/               # Configuration files
│   ├── defaults.conf      # Default values
│   └── examples/          # Example configs
├── aws/                   # AWS Terraform
├── azure/                 # Azure Terraform
├── gcp/                   # GCP Terraform
├── vsphere/               # vSphere Terraform
├── nutanix/               # Nutanix Terraform
├── none/                  # Bare metal Terraform
└── docs/                  # Documentation
```

## Adding New Features

### Adding a New Cloud Platform

1. Create directory: `mkdir <platform>/`
2. Add Terraform files:
   - `main.tf` - Provider and resources
   - `variables.tf` - Input variables
   - `windows-vm-bootstrap.tf` - Bootstrap script
3. Update `lib/platform.sh`:
   - Add platform to `SUPPORTED_PLATFORMS`.
   - Add `get_<platform>_terraform_args()` function.
   - Add `get_user_name()` case.
4. Update `lib/credentials.sh`:
   - Add `export_<platform>_credentials()` function.
5. Create example config: `configs/examples/<platform>.conf.example`
6. Add documentation: `docs/platforms/<platform>.md`
7. Update README.md

### Adding a Configuration Option

1. Add to `configs/defaults.conf` with default value.
2. Update `configs/examples/defaults.conf.example`.
3. Add variable to relevant Terraform `variables.tf`.
4. Update `lib/platform.sh` to pass the variable.
5. Document in README.md.
6. Add example usage

## Commit Message Guidelines

- Use present tense ("Add feature" not "Added feature").
- Use imperative mood ("Move cursor to..." not "Moves cursor to...").
- Limit first line to 72 characters.
- Reference issues and pull requests liberally.

Examples:
```
Add support for custom Windows image versions in Azure.

Parameterize all hardcoded values in AWS Terraform.

Fix credential loading for vSphere platform.

Update documentation for configuration system.
```

## Release Process

1. Update VERSION file.
2. Update CHANGELOG.md.
3. Create release tag.
4. Create GitHub release with notes.

## Getting Help

- **GitHub Issues**: For bugs and feature requests
- **Discussions**: For questions and general discussion
- **Documentation**: Check docs/ directory

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Recognition

Contributors will be recognized in:
- GitHub contributors page
- CHANGELOG.md for significant contributions
- Project documentation

Thank you for contributing to BYOH Provisioner!
