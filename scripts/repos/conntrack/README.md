# Mock `conntrack`

The `conntrack` package is required by `kubectl`, but on SLES `conntrack` is actually provided by `conntrack-tools`.
Unfortunately `kubectl` doesn't recognize this, and will fail to install if it can't find a package named `conntrack`.

The fault lies in the `kubectl` packaging and/or in the `conntrack-tools` packaging.

- `conntrack-tools` isn't identifying to `kubectl` that it provides `conntrack`
- `kubectl` isn't recognizing it is on a SUSE distro, where it should require `conntrack-tools` instead

To work around this nonsense we create our own nonsense by installing `conntrack-tools` and then creating a mock `conntrack` RPM.
The `conntrack.spec` file creates a lemon, it installs nothing and does nothing but it fools `kubectl` into thinking
`conntrack` is being provided.
