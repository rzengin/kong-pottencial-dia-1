# ============================================================================
# VARIABLES — Certificados y endpoints del Control Plane
# Extraídos del dp2.sh original y separados en variables para reutilización
# ============================================================================

variable "cluster_control_plane" {
  description = "Endpoint del Control Plane de Konnect (host:port)"
  type        = string
  default     = "83897e20f5.us.cp.konghq.com:443"
}

variable "cluster_server_name" {
  description = "SNI del Control Plane"
  type        = string
  default     = "83897e20f5.us.cp.konghq.com"
}

variable "cluster_telemetry_endpoint" {
  description = "Endpoint de telemetría de Konnect"
  type        = string
  default     = "83897e20f5.us.tp.konghq.com:443"
}

variable "cluster_telemetry_server_name" {
  description = "SNI del endpoint de telemetría"
  type        = string
  default     = "83897e20f5.us.tp.konghq.com"
}

variable "cluster_cert" {
  description = "Certificado mTLS del Data Plane (PEM)"
  type        = string
  sensitive   = true
  default     = <<-EOT
    -----BEGIN CERTIFICATE-----
    MIICHTCCAcSgAwIBAgIBATAKBggqhkjOPQQDBDBAMT4wCQYDVQQGEwJVUzAxBgNV
    BAMeKgBrAG8AbgBuAGUAYwB0AC0ATABvAGMAYQBsACAARwBhAHQAZQB3AGEAeTAe
    Fw0yNjAzMjMxMzQ2NTJaFw0zNjAzMjMxMzQ2NTJaMEAxPjAJBgNVBAYTAlVTMDEG
    A1UEAx4qAGsAbwBuAG4AZQBjAHQALQBMAG8AYwBhAGwAIABHAGEAdABlAHcAYQB5
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAENI2f0P4XvO9gr0RNuDtBCpASxJBo
    WNNXoZLvgG5WH+8pPxJuE9I7JVuF+21XrV88SwRWXq3eQ909woGZnz+WpKOBrjCB
    qzAMBgNVHRMBAf8EAjAAMAsGA1UdDwQEAwIABjAdBgNVHSUEFjAUBggrBgEFBQcD
    AQYIKwYBBQUHAwIwFwYJKwYBBAGCNxQCBAoMCGNlcnRUeXBlMCMGCSsGAQQBgjcV
    AgQWBBQBAQEBAQEBAQEBAQEBAQEBAQEBATAcBgkrBgEEAYI3FQcEDzANBgUpAQEB
    AQIBCgIBFDATBgkrBgEEAYI3FQEEBgIEABQACjAKBggqhkjOPQQDBANHADBEAiBk
    6tttV7YJB43V8srs46hurlAs9zwdZ/Bv3f2VIAviogIgCNamOMYbFk8TyDT30T7n
    IHDBl5PMSOu9fGatVUiMSYI=
    -----END CERTIFICATE-----
  EOT
}

variable "cluster_cert_key" {
  description = "Clave privada mTLS del Data Plane (PEM)"
  type        = string
  sensitive   = true
  default     = <<-EOT
    -----BEGIN PRIVATE KEY-----
    MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQghD1E05q822l4zTEU
    Y6rVoNzuCDLw+UMvxEhvKkg/5lagCgYIKoZIzj0DAQehRANCAAQ0jZ/Q/he872Cv
    RE24O0EKkBLEkGhY01ehku+AblYf7yk/Em4T0jslW4X7bVetXzxLBFZerd5D3T3C
    gZmfP5ak
    -----END PRIVATE KEY-----
  EOT
}
