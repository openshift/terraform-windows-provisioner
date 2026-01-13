# Security Policy

## Reporting Security Issues

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities to the Red Hat Product Security team:

- Email: prodsec-openshift@redhat.com
- For more information: https://access.redhat.com/security/team/contact

Please include the following information in your report:

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Suggested fix (if available)

## Supported Versions

This project follows the OpenShift support lifecycle. Security updates are provided for:

- The latest release version
- Versions compatible with currently supported OpenShift releases

## Security Best Practices

When using this tool:

1. **Credentials**: Never commit credentials to version control.
2. **Secrets**: Use Kubernetes secrets for sensitive data.
3. **Access Control**: Limit access to service accounts and API keys.
4. **Network Security**: Follow your organization's network security policies.
5. **Updates**: Keep Terraform and dependencies up to date.

## Known Security Considerations

- Cloud provider credentials are required and should be managed securely.
- Windows admin passwords are used for provisioning - use strong passwords.
- SSH keys are extracted from cluster secrets - ensure proper RBAC is configured.
