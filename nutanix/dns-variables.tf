# DNS variables for PTR record management (WINC-1633)

variable "dns_server" {
  description = "DNS server address for RFC 2136 updates"
  type        = string
  default     = ""
}

variable "dns_domain" {
  description = "DNS domain for Windows instance FQDNs (e.g., winc.devcluster.openshift.com)"
  type        = string
  default     = ""
}

variable "dns_reverse_zone" {
  description = "Reverse DNS zone (e.g., '0.10.in-addr.arpa.' for 10.0.0.0/16)"
  type        = string
  default     = ""
}

variable "dns_key_name" {
  description = "TSIG key name for RFC 2136 authentication"
  type        = string
  default     = "update-key"
}

variable "dns_key_algorithm" {
  description = "TSIG key algorithm"
  type        = string
  default     = "hmac-sha256"
}

variable "dns_key_secret" {
  description = "Base64-encoded TSIG key secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_ptr_records" {
  description = "Enable PTR record creation for BYOH Windows instances"
  type        = bool
  default     = false
}

variable "validate_ptr_records" {
  description = "Run nslookup validation after PTR record creation"
  type        = bool
  default     = false
}
