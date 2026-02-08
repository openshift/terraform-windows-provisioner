# FIPS 140-2 Configuration Variable
# Symlinked from all platform directories (aws, azure, gcp, vsphere, nutanix, none)

# Enable FIPS 140-2 mode (optional)
variable "fips_enabled" {
    type        = bool
    default     = false
    description = "Enable FIPS 140-2 mode for Windows instances. Requires RSA 4096 SSH key (not curve25519). Configures Windows registry and SSH for FIPS-compliant algorithms only."
}
