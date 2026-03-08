#!/bin/bash
# Retrieves the Ansible vault password from macOS Keychain.
#
# To store the password (one-time setup):
#   security add-generic-password -a dudlab-ansible-vault -s "Ansible Vault" -w
#
# Ansible calls this script automatically via ansible.cfg:
#   vault_password_file = scripts/vault-pass.sh
set -euo pipefail

password=$(security find-generic-password -a "dudlab-ansible-vault" -w 2>/dev/null) || {
  echo "ERROR: Vault password not found in Keychain." >&2
  echo "Run: security add-generic-password -a dudlab-ansible-vault -s \"Ansible Vault\" -w" >&2
  exit 1
}

echo "$password"
