#!/usr/bin/env just --justfile

# Root justfile for wjmca Certificate Authority
# Delegates to CA-specific justfiles

set shell := ["bash", "-euo", "pipefail"]

PROJECT_ROOT := justfile_directory()
ROOT_CA_DIR := PROJECT_ROOT + "/root-ca"
INTERMEDIATE_CA_DIR := PROJECT_ROOT + "/intermediate-ca"

# Display all available recipes
help:
    @just --list

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize all CA directories and databases
init-dirs:
    #!/bin/bash
    set -euo pipefail
    echo "Initializing CA directories..."

    # Root CA
    touch "{{ ROOT_CA_DIR }}/index.txt" 2>/dev/null || echo "Root index exists"
    echo 1000 > "{{ ROOT_CA_DIR }}/serial" 2>/dev/null || echo "Root serial exists"
    mkdir -p "{{ ROOT_CA_DIR }}/crl" "{{ ROOT_CA_DIR }}/newcerts"

    # Intermediate CA
    touch "{{ INTERMEDIATE_CA_DIR }}/index.txt" 2>/dev/null || echo "Intermediate index exists"
    echo 1000 > "{{ INTERMEDIATE_CA_DIR }}/serial" 2>/dev/null || echo "Intermediate serial exists"
    mkdir -p "{{ INTERMEDIATE_CA_DIR }}/crl" "{{ INTERMEDIATE_CA_DIR }}/newcerts"

    echo "✓ CA directories initialized"

# ============================================================================
# ROOT CA OPERATIONS
# ============================================================================

# Generate root CA private key (Ed25519)
root-gen-key algorithm="ed25519":
    @just -f {{ ROOT_CA_DIR }}/justfile gen-key {{ algorithm }}

# Generate root CA private key (RSA fallback for legacy support)
root-gen-key-rsa bits="4096":
    @just -f {{ ROOT_CA_DIR }}/justfile gen-key-rsa {{ bits }}

# Create root CA self-signed certificate
root-gen-cert:
    @just -f {{ ROOT_CA_DIR }}/justfile gen-cert

# Generate CSR from root CA key
root-csr:
    @just -f {{ ROOT_CA_DIR }}/justfile gen-csr

# Sign an intermediate CA certificate request
root-sign-intermediate csr-path:
    @just -f {{ ROOT_CA_DIR }}/justfile sign-intermediate {{ csr-path }}

# View root CA certificate details
root-inspect:
    @just -f {{ ROOT_CA_DIR }}/justfile inspect

# Show root CA status
root-status:
    @just -f {{ ROOT_CA_DIR }}/justfile status

# ============================================================================
# INTERMEDIATE CA OPERATIONS
# ============================================================================

# Initialize intermediate CA (must have signed cert from root)
intermediate-setup:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile setup

# Generate intermediate CA private key (Ed25519)
intermediate-gen-key algorithm="ed25519":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-key {{ algorithm }}

# Generate intermediate CA private key (RSA fallback)
intermediate-gen-key-rsa bits="4096":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-key-rsa {{ bits }}

# Generate CSR for intermediate CA certificate signing
intermediate-csr:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-csr

# Install signed intermediate certificate
intermediate-install-cert cert-path:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile install-cert {{ cert-path }}

# Generate CSR for end-entity certificate
intermediate-gen-end-entity-csr cn st="Stockholm" c="SE" org="Organization" ou="IT":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-end-entity-csr {{ cn }} {{ st }} {{ c }} {{ org }} {{ ou }}

# Issue certificate from CSR
intermediate-issue-cert csr-path:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile issue-cert {{ csr-path }}

# Generate key + multi-SAN CSR for a TLS server (LAN IP + Tailscale + hostnames)
intermediate-gen-server-csr cn sans algorithm="ecdsa":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-server-csr {{ cn }} {{ sans }} {{ algorithm }}

# Issue TLS server certificate from a multi-SAN CSR (v3_server_cert profile)
intermediate-issue-server-cert csr-path days="825":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile issue-server-cert {{ csr-path }} {{ days }}

# Revoke a certificate
intermediate-revoke cert-path reason="unspecified":
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile revoke {{ cert-path }} {{ reason }}

# Generate Certificate Revocation List
intermediate-gen-crl:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile gen-crl

# View intermediate CA certificate
intermediate-inspect:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile inspect

# Show intermediate CA status
intermediate-status:
    @just -f {{ INTERMEDIATE_CA_DIR }}/justfile status

# ============================================================================
# INSPECTION & UTILITIES
# ============================================================================

# View details of any certificate
inspect-cert cert-path:
    #!/bin/bash
    set -euo pipefail
    if [[ ! -f "{{ cert-path }}" ]]; then
        echo "❌ Certificate not found: {{ cert-path }}"
        exit 1
    fi
    echo "📋 Certificate: {{ cert-path }}"
    openssl x509 -in "{{ cert-path }}" -text -noout

# Verify a certificate against a CA
verify-cert cert-path ca-cert:
    #!/bin/bash
    set -euo pipefail
    if ! openssl verify -CAfile "{{ ca-cert }}" "{{ cert-path }}"; then
        echo "❌ Certificate verification failed"
        exit 1
    fi
    echo "✓ Certificate verified successfully"

# Show certificate validity period
check-expiry cert-path:
    #!/bin/bash
    set -euo pipefail
    openssl x509 -in "{{ cert-path }}" -noout -dates
