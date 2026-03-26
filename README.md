# mise-zephyr-sdk-plugin

A [mise](https://mise.jdx.dev/) backend plugin for the [Zephyr SDK](https://github.com/zephyrproject-rtos/sdk-ng) (arm-zephyr-eabi toolchain).

## What it does

Downloads and installs three components from Zephyr SDK GitHub releases:

1. **Minimal SDK** (`zephyr-sdk-<ver>_<platform>_minimal.tar.xz`) - cmake files, sdk_version, setup scripts
2. **ARM toolchain** (`toolchain_<platform>_arm-zephyr-eabi.tar.xz`) - cross-compiler for ARM targets
3. **Hosttools** (`hosttools_<platform>.tar.xz`) - host build tools (Linux only, self-extracting installer)

Sets `ZEPHYR_SDK_INSTALL_DIR`, `ZEPHYR_TOOLCHAIN_VARIANT=zephyr`, and adds toolchain + hosttools bins to `PATH`.

## Usage

```bash
# Install the plugin
mise plugin install zephyr-sdk https://github.com/ale-alfaro/mise-zephyr-sdk-plugin

# List available versions
mise ls-remote zephyr-sdk:zephyr-sdk

# Install a specific version
mise install zephyr-sdk:zephyr-sdk@0.17.0

# Use in a project
mise use zephyr-sdk:zephyr-sdk@0.17.0
```

## Environment variables

| Variable | Value |
|---|---|
| `PATH` | `<install>/arm-zephyr-eabi/bin` (or `<install>/gnu/arm-zephyr-eabi/bin` for SDK >= 1.0.0) |
| `PATH` | `<install>/x86_64-zephyr-elf/bin` (Linux only) |
| `ZEPHYR_SDK_INSTALL_DIR` | `<install>` (SDK root with cmake/ and sdk_version) |
| `ZEPHYR_TOOLCHAIN_VARIANT` | `zephyr` |

## Development

### Local testing

```bash
mise plugin link --force zephyr-sdk .
mise run smoke-test
```

### Code quality

```bash
mise run lint       # Run all linters
mise run format     # Format Lua code
mise run ci         # Full CI suite
```

### Debugging

```bash
MISE_DEBUG=1 mise install zephyr-sdk:zephyr-sdk@0.17.0
```

## Files

- `metadata.lua` - Plugin metadata
- `hooks/backend_list_versions.lua` - Lists available versions from GitHub releases
- `hooks/backend_install.lua` - Downloads and installs the SDK (minimal SDK + toolchains via setup.sh)
- `hooks/backend_exec_env.lua` - Configures PATH, ZEPHYR_SDK_INSTALL_DIR, ZEPHYR_TOOLCHAIN_VARIANT
- `lib/zephyr_sdk.lua` - Shared library for GitHub API, platform detection, asset resolution
- `mise-tasks/smoke-test` - Quick install and verify test
- `mise-tasks/integration-test` - Full Zephyr build test

## License

MIT
