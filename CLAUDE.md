# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project: wjmca (Certificate Authority)

A secure, best-practice Certificate Authority (CA) for
internal organizational PKI, built around justfile
automation and org-mode documentation. The CA uses an
offline root with online intermediates, Yubikey
protection for the root key, and the `pass` utility
for secret management.

### Vision

- **Security-first**: Follows industrial best practices
  for CA operations
- **Offline root CA**: Protected by Yubikey, kept
  off the network
- **Online intermediate CA(s)**: Handles day-to-day
  certificate issuance
- **Team-friendly**: Justfile automation reduces
  manual steps and human error
- **Well-documented**: Operational procedures in
  org-mode for clarity and audit trail
- **Share-safe**: No secrets committed to git;
  repository can be shared publicly without
  compromising security

## Repository Structure

```
wjmca/
├── CLAUDE.md                 (this file)
├── README.org                (operations manual)
├── yubikey.org               (Yubikey setup guide)
├── .gitignore                (prevents secret commits)
├── justfile                  (root-level recipes)
│
├── root-ca/
│   ├── justfile              (offline CA operations)
│   ├── openssl.cnf           (root CA config)
│   ├── certs/                (public root cert)
│   ├── csr/                  (CSRs to root)
│   └── private/              (⚠️ GITIGNORED: key)
│
├── intermediate-ca/
│   ├── justfile              (online CA operations)
│   ├── openssl.cnf           (intermediate config)
│   ├── certs/                (intermediate cert)
│   ├── csr/                  (incoming CSRs)
│   ├── newcerts/             (issued certs)
│   └── private/              (⚠️ GITIGNORED: key)
│
└── docs/ (optional future)
    ├── security-policy.org   (PKI policy)
    ├── procedures.org        (detailed procedures)
    └── audit-log.org         (operation records)
```

## Setup & Prerequisites

### Local Development Environment

Before working with the CA, ensure:

1. **just** is installed:
   ```
   curl --proto '=https' --tlsv1.2 -sSf \
     https://just.systems/install.sh | bash
   ```
2. **openssl** is available (version 1.1.1+)
3. **pass** utility installed for secret management
4. **Yubikey** available (if managing root CA)

### Initial Setup

```bash
# Initialize directory structure
just init-dirs

# Root keeper setup
just root-setup

# Intermediate manager setup
just intermediate-setup
```

## Common Commands

All commands run from project root using `just`.
The root justfile delegates to CA-specific justfiles:

### Root CA Operations (offline, restricted)

```bash
# Initialize root CA infrastructure
just root-setup

# Generate root certificate signing request
just root-csr

# Self-sign root CA certificate
just root-self-sign

# Sign an intermediate CSR
just root-sign-csr <csr-file>

# View root certificate details
just root-inspect
```

### Intermediate CA Operations (online, team)

```bash
# Initialize intermediate CA infrastructure
just intermediate-setup

# Generate CSR (to be signed by root)
just intermediate-csr

# Install signed intermediate certificate
just intermediate-install-cert <signed-cert>

# Issue an end-entity certificate
just intermediate-issue-cert <csr-file>

# Generate CSR for end-entity certificate
just intermediate-gen-csr <cn-name> [c] [st] [l] \
  [o] [ou]

# Revoke a certificate
just intermediate-revoke <cert-file>

# View intermediate CA details
just intermediate-inspect

# Generate CRL (Certificate Revocation List)
just intermediate-gen-crl
```

### Status & Inspection

```bash
# Show all available recipes
just --list

# Check root CA status
just root-status

# Check intermediate CA status
just intermediate-status

# View certificate details
just inspect-cert <path>
```

## Security Model

### Key Protection

- **Root CA Private Key**: Protected by Yubikey,
  never leaves offline machine. Access controlled by
  single "root-keeper".
- **Intermediate CA Private Key**: Encrypted with
  passphrase via `pass` utility.
- **Passphrases**: Never hardcoded; referenced as
  `$(pass show ca/intermediate-passphrase)` etc.

### Secret Management with `pass`

Secrets managed through `pass` password manager:

```bash
# Add intermediate CA passphrase
pass insert ca/intermediate-passphrase

# Retrieve in justfile recipe
{{ `pass show ca/intermediate-passphrase` }}
```

### Git Protection

The `.gitignore` file strictly prevents secret
commits:

```
root-ca/private/
intermediate-ca/private/
*.key
*.p8
*.pem
!*.pub.pem
```

**Critical**: Before committing, verify no secrets
staged:
```bash
git diff --cached -- root-ca/private \
  intermediate-ca/private
```

## Team Roles & Workflows

### Root Keeper

- **Responsibility**: Maintains offline root CA
  and Yubikey
- **Access**: Only person with root-ca/ access on
  offline machine
- **Actions**: Signs intermediate CSRs; performs
  root key rotation (rare)
- **Workflow**:
  1. Receives CSR from intermediate team
  2. Transfers CSR to offline machine via
     secure media (USB)
  3. Signs with `just root-sign-csr <csr-file>`
  4. Transfers signed cert back
  5. Logs action in audit trail

### Intermediate Manager

- **Responsibility**: Day-to-day certificate
  issuance and revocation
- **Access**: Online access to intermediate-ca/
- **Actions**: Issues end-entity certs, manages
  CSRs, generates CRLs
- **Workflow**:
  1. Receives certificate request
  2. Generates CSR:
     `just intermediate-gen-csr "example.org"`
  3. Issues cert:
     `just intermediate-issue-cert <csr>`
  4. Distributes cert to requestor
  5. Logs issuance in audit trail

### Optional: Auditor

- Read-only access to certificate records
  and audit logs
- Reviews monthly CA activity and compliance

## Development Guidelines

### Adding New Justfile Recipes

When extending justfiles (root-ca/justfile or
intermediate-ca/justfile):

1. **Document** recipe with comments explaining
   purpose
2. **Use environment variables** for paths:
   `CA_DIR := justfile_directory()`
3. **Reference secrets** via `pass`:
   `{{ `pass show ca/...` }}`
4. **Include dry-run** mode for destructive
   operations
5. **Log operations** to audit trail
   (docs/audit-log.org)

Example recipe:

```justfile
# Issue a certificate for the given CSR
issue-cert csr-file:
    #!/bin/bash
    set -euo pipefail
    openssl ca -in {{ csr-file }} \
      -out newcerts/$(basename {{ csr-file }} \
        .csr).crt \
      -passin pass:$(pass show \
        ca/intermediate-passphrase) \
      -config openssl.cnf
    echo "✓ Certificate issued"
```

### OpenSSL Configuration

- **root-ca/openssl.cnf**: Strict root CA config
  (short validity, limited key usage)
- **intermediate-ca/openssl.cnf**: Intermediate
  config (longer validity, broader constraints)

Both should define:
- Certificate paths and naming conventions
- Default validity periods (root: 20y,
  intermediate: 10y, end-entity: 1-3y)
- Key algorithm and size defaults
- Subject name handling

### Cryptographic Defaults

- **Primary**: Ed25519 keys (modern, small, fast)
- **Legacy support**: RSA-4096 (for devices
  like Grandstream SIP adapters)
- **Avoid**: SHA-1, RSA < 2048, DES

### Org-Mode Documentation

The README.org file serves as the operational
manual. Update it when:
- Adding new procedures or recipes
- Changing security policies
- Documenting incidents or lessons learned
- Updating team contacts or responsibilities

## Claude Code Behavior

**Package Installation**: Do not install system
packages directly. Only recommend that packages
should be installed and provide the installation
commands for the user to run. The user controls
their environment and can install packages when
ready.

## Considerations for Future Work

- **CRL Distribution**: Plan how intermediate CA
  publishes its CRL (HTTP endpoint, file
  transfer, etc.)
- **OCSP Responder**: Consider adding OCSP for
  real-time certificate status queries
- **Backup Strategy**: Define backup/recovery
  procedures for intermediate CA (encrypted
  backups of key material)
- **Monitoring & Alerting**: Log certificate
  issuances and set up alerts for unusual
  activity
- **Compliance**: Document compliance with
  relevant standards (RFC 5280, organizational
  policy, industry regulations)

## Common Pitfalls to Avoid

1. **Committing secrets**: Always verify
   `.gitignore` works before committing
2. **Reusing CSRs**: Generate new CSRs for each
   certificate; don't reuse
3. **Key rotation**: Plan periodic root CA key
   rotation (every 10+ years); intermediate
   more frequently
4. **Expiry tracking**: Set calendar reminders
   for certificate renewal (3-6 months before
   expiry)
5. **Audit trails**: Log all CA operations;
   don't skip this even in testing
