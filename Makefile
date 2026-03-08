.DEFAULT_GOAL := help

# One-time setup: store the vault password in macOS Keychain
#   security add-generic-password -a dudlab-ansible-vault -s "Ansible Vault" -w

.PHONY: help ping deploy update lint install-deps setup-vault

help:
	@echo "dudlab-cluster targets:"
	@echo "  make ping          Test connectivity to all nodes"
	@echo "  make deploy        Run full site.yml (provision + all services)"
	@echo "  make update        Update packages on all nodes"
	@echo "  make lint          Run ansible-lint and yamllint"
	@echo "  make install-deps  Install Ansible collections from requirements.yml"
	@echo "  make setup-vault   One-time: store vault password in macOS Keychain"

ping:
	ansible-playbook playbooks/ping.yml

deploy:
	ansible-playbook site.yml

update:
	ansible-playbook playbooks/update.yml

lint:
	yamllint .
	ansible-lint

install-deps:
	ansible-galaxy collection install -r requirements.yml -p .ansible/collections

setup-vault:
	@echo "Enter the Ansible vault password when prompted:"
	@security add-generic-password -a "dudlab-ansible-vault" -s "Ansible Vault" -w \
		&& echo "Vault password stored in Keychain." \
		|| echo "Failed — password may already exist. Use Keychain Access to update it."
