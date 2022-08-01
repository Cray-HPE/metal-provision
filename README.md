# Metal Provisioning

Ansible for building and configuring non-compute nodes.

## Ansible Config

The `ansible.cfg` file in this repository is copied into an NCN image during build-time.

## Roles & Playbooks

Playbooks live in the root of the repository, those prefixed with `^pb` are used in the packer build
pipeline.

- `packer.yml` inventory file for packer builds
- `^pb*` playbooks for packer builds
