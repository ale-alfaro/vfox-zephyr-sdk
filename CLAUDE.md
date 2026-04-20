# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A mise backend plugin for the Zephyr SDK. It manages installation of Zephyr toolchains (GNU/LLVM), host tools, Nordic NCS bundles, and a `west` CLI shim powered by uv scripts (no venv needed).

## Commands

```bash
# Lint (lua-language-server type checking at Error level)
mise run lint

# Format Lua code
mise run format          # uses StyLua (stylua.toml)

# Test
mise run smoke_test      # quick: lists versions + runs tool commands from tests/tools.txt
mise run integration_test  # full: west init + west build with a real Zephyr sample
mise run ci              # lint + smoke_test + integration_test

# Local plugin testing (link, clear cache, then install/use)
mise plugin link --force zephyr-sdk-test .
mise cache clear
mise install zephyr-sdk-test:arm-zephyr-eabi@0.17.0
mise x zephyr-sdk-test:west@0.17.0 -- west --version

# Debug logging
MISE_DEBUG=1 mise install zephyr-sdk-test:west@0.17.0
```

CI tasks are defined in `mise.ci.toml`. Local dev tools (`uv`, `lua-language-server`) are configured in `mise.local.toml`.

## Lua Runtime

The plugin runs under **gopher-lua (Lua 5.1)**, not standard Lua 5.4. This affects available builtins and standard library. Linter/LSP configs (`.luarc.json`, `.luacheckrc`) are set to `Lua 5.1`.

## Architecture

### Hook-based plugin model

Mise calls three hooks in `hooks/`:
- `backend_list_versions.lua` -- returns available versions for a tool
- `backend_install.lua` -- downloads and installs the requested tool+version
- `backend_exec_env.lua` -- sets environment variables (PATH, ZEPHYR_SDK_INSTALL_DIR, etc.)

Each hook dispatches to the appropriate tool module via `ZephyrSdk[tool_name]`.

### Tool registry with lazy loading

`lib/zephyr_sdk.lua` is the central registry. It uses a metatable `__index` to lazy-load tool modules on first access. Alias mapping:
- `"arm-zephyr-eabi"`, `"llvm"`, etc. -> `lib/toolchain.lua`
- `"west"` -> `lib/west.lua`
- `"ncs"` -> `lib/ncs_toolchain.lua`

Each tool module exports `list_versions()`, `install(ctx)`, and `envs(ctx)`.

### Mise-provided globals and modules

Four globals are injected by the mise runtime (declared in `.luarc.json` and `.luacheckrc`):
- `PLUGIN` -- plugin metadata from `metadata.lua`
- `RUNTIME` -- mise runtime context
- `Utils` -- utility library (loaded from `lib/utils/`)
- `ZephyrSdk` -- the tool registry

Mise also provides these via `require`: `cmd`, `http`, `json`, `archiver`, `file`, `log`.

### Version caching

`lib/utils/store.lua` caches version data to JSON files with a 12-hour TTL to avoid excessive GitHub/Artifactory API calls.

### West shim (PEP 723)

`lib/west.lua` generates a Python uv script with inline metadata (`# /// script` block). Dependencies are resolved at runtime by uv -- no virtualenv needed. The generated shim is placed in the install path and made executable.

## Code Style

- StyLua formatting: 4-space indent, 120-char line width, Unix line endings (`stylua.toml`)
- Unused args prefixed with `_`
- Type annotations in `types/mise-plugin.lua`; type stubs excluded from luacheck
