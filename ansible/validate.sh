#!/bin/bash
set -e

cd "$(dirname "$0")"

# Run ansible-playbook syntax check
ansible-playbook -i inventory.ini site.yml --syntax-check
