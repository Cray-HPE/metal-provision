# Metal Provisioning

Ansible for building and configuring non-compute nodes.

## Ansible Config

The `ansible.cfg` file in this repository is copied into an NCN image during build-time.

## Roles & Playbooks

Playbooks live in the root of the repository, those prefixed with `^pb` are used in the packer build
pipeline.

- `packer.yml` inventory file for packer builds
- `^pb*` playbooks for packer builds and may not run when invoked on a live system.
- All other playbooks may be ran on a live system at `/srv/cray/metal-provision/` using either (depending on which is available):
    - Legacy Location:`/etc/ansible/csm_ansible/bin/ansible-playbook`
    - New location:`/opt/cray/ansible/bin/ansible-playbook`
