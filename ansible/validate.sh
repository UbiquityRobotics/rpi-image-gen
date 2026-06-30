#!/bin/bash
set -e

# Run ansible-playbook syntax check
ansible-playbook -i inventory.ini site.yml --syntax-check
