# Villode Caelestia Shell

This fork is the controlled Caelestia Shell base used by
[Villode Caelestia](https://github.com/Villode/villode-caelestia).

- `main` follows the upstream development branch.
- `villode` is the tested integration branch.
- `UPSTREAM_VERSION` records the stable upstream release currently adapted.
- Simplified Chinese remains an optional patch and is not baked into the base shell.

The controlled branch also disables runtime source watching and moves the unsupported `DefaultEnv`
pragmas into the launcher wrapper. These are deliberate compatibility and idle-resource changes.

## Updating from upstream

Updates are intentionally manual so an upstream change cannot silently break the Chinese patch,
Dock, Desktop or Launcher integration.

```bash
git fetch upstream --tags
git switch villode
git merge --no-ff vNEXT
```

After resolving changes:

1. Update `UPSTREAM_VERSION`.
2. Run `bash -n install-villode.sh uninstall-villode.sh`.
3. Build and install into an isolated home.
4. Rebase or regenerate the Chinese patch against the new source.
5. Test Caelestia together with Dock, Desktop and Launcher.
6. Push `villode`, then update the locked commit in `villode-caelestia/components.tsv`.

Do not update the integration manifest before the compatibility tests pass.
