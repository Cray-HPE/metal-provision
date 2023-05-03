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

## Packages

Packages are controlled by role variables, typically in a file following the path structure of:

```bash
roles/<role>/vars/packages/<distro>[-<arch>].yml
```

### Adding new Distros

1. Add a new YAML file for the distro. The `<distro>` name needs to match the Ansible fact `ansible_distribution_file_variety | lower`.

1. Update the `tasks/packages.yml` file for the new distro and package manager, simply copy-paste one of the other distro's `block`s
   and refactor it for the appropriate package manager module.

> ***NOTE*** The `<arch>` is optional. Defining a YAML by `<distro>` without an `<arch>` value implies that the packages listed
> are intended for all architectures.

### Adding architecture specific package lists

The package installation tasks already search for architectures depending on the environment, to add a new architecture 
one can simply drop a new YAML file for the appropriate `<distro>` (the value returned by `ansible_distribution_file_variety | lower`)
and `-<arch>` (the value returned by `ansible_architecture`).

> ***NOTE*** There must always be a `<distro>.yml` file before there can be any `<distro>-<arch>.yml` files.
