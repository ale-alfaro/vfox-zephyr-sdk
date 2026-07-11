# vfox-zephyr-sdk

A [mise](https://mise.jdx.dev/) backend plugin for the [Zephyr SDK](https://github.com/zephyrproject-rtos/sdk-ng).

## What it does

### Support for all Zephyr SDK toolchains and host tools

**Downloads and installs the major toolchains from Zephyr SDK GitHub releases**

1. **Minimal SDK** (`zephyr-sdk-<ver>_<platform>_minimal.tar.xz`) - cmake files, sdk_version, setup scripts
2. **Zephyr/GNU Target Toolchain** (`toolchain_<platform>_arm-zephyr-eabi.tar.xz`) - cross-compiler for targets
3. **LLVM Toolchain** (`toolchain_<platform>_llvm.tar.xz`) - LLVM toolchain (Zephyr-SDK 1.0.0+ only!)
4. **Hosttools** (`hosttools_<platform>.tar.xz`) - host tools such as opencod and qemu (Linux only, self-extracting installer)

### Multiple toolchain variants

Zephyr picks a compiler through `ZEPHYR_TOOLCHAIN_VARIANT`. This plugin exposes
each supported variant as its own mise tool, so the **tool name is the variant**
— no options to remember, nothing to get confused about:

| Tool name(s)                              | `ZEPHYR_TOOLCHAIN_VARIANT` | Source                                   | Tool options |
| ----------------------------------------- | -------------------------- | ---------------------------------------- | ------------ |
| `arm`, `aarch64`, `riscv64`, `x86_64`, …  | `zephyr`                   | Zephyr SDK GNU cross-compilers           | none (target fixed by name) |
| `toolchain`                               | `zephyr`                   | Zephyr SDK GNU cross-compilers           | `toolchains`, `hosttools`, `cmake_pkg` |
| `llvm`                                    | `llvm`                     | Zephyr SDK LLVM/Clang (**>= 1.0.0**)     | none |
| `gnuarmemb`                               | `gnuarmemb`                | Arm GNU Toolchain (`arm-none-eabi`)      | none |

Switching is just switching tools:

```bash
mise use zephyr-sdk:arm@0.17.0           # ZEPHYR_TOOLCHAIN_VARIANT=zephyr
mise use zephyr-sdk:llvm@1.0.0           # ZEPHYR_TOOLCHAIN_VARIANT=llvm
mise use zephyr-sdk:gnuarmemb@15.2.rel1  # ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
```

`llvm` and `gnuarmemb` are **standalone, option-less** tools: the tool name is
the whole configuration, so there is nothing to get wrong.

**The GNU (`zephyr`) side never installs everything.** The arch tools each
install exactly their one target. The general `toolchain` tool takes options and
**defaults to installing only `arm-zephyr-eabi`** when given none:

```bash
mise install zephyr-sdk:toolchain@0.17.0                       # -> arm-zephyr-eabi only
mise install zephyr-sdk:toolchain@0.17.0 --toolchains=riscv64  # pick another target
mise install zephyr-sdk:toolchain@0.17.0 --hosttools --cmake_pkg  # opt in to extras
```

Host tools and CMake-package registration are always **opt-in**, off by default.

`gnuarmemb` is managed independently of the Zephyr SDK: its own download source
(Arm), version scheme (e.g. `15.2.rel1`), and install path. Any Arm-published
version works, not just the ones shown by `ls-remote`.

### West via uv script

**Creates a shim of west using uv scripts with inline metadata for dependency management and keeping them self-contained**

No more .venv required to build with west. The uv script handles the dependancy management for you in the background. **YOU NEED UV INSTALLED AND IN YOUR PATH**

## How does this work?

### Zephyr SDK

The Zephyr SDK tools all leverage the minimal SDK installer script `setup.sh` and install the all toolchains under `~/zephyr-sdk-root/` following the Zephyr conventions `~/zephyr-sdk-root/zephyr-sdk-<VERSION>/<TOOLCHAIN>` where toolchain can be one of the toolchains listed in the sdk_toolchains file that comes with the Zephyr SDK installations.
The mise integration is done using **symlinks** to the bin paths for the toolchains installed. Also every time a tool is run the `ZEPHYR_SDK_INSTALL_DIR` and `ZEPHYR_TOOLCHAIN_VARIANT` will be present. That way we don't mess with Zephyr toolchain search heuristics and can find the toolchains without a hitch.

### Compatibility between Zephyr-SDK and Zephyr the Project

The table below is from the [compatiblity matrix mantained by zephyrproject-rtos/sdk-ng](https://docs.google.com/spreadsheets/d/1wzGJLRuR6urTgnDFUqKk7pEB8O6vWu6Sxziw_KROxMA/edit?usp=sharing). The plugin does its best to adhere to this compatiblity matrix but leaning towards having less versions supported than available ones.

| version | main | 4.4.0 | 4.3.0 | 4.2.0 | 4.1.0 | 4.0.0 |
| ------- | ---- | ----- | ----- | ----- | ----- | ----- |
| 1.0.1   | Y    | Y     | N     | N     | N     | N     |
| 1.0.0   | Y    | Y     | N     | N     | N     | N     |
| 0.17.4  | N    | N     | Y     | Y     | P     | P     |
| 0.17.0  | N    | N     | Y     | Y     | Y     | Y     |

### West

You can read more about [uv scripts]() but the gist is that they contain comments at the top of the file following [Python's inline script metadata spec](https://packaging.python.org/en/latest/specifications/inline-script-metadata/#inline-script-metadata) which look something like this:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
```

With these, uv can run and install your script with dependencies installed on-demand. You run it using the `uv run --script` command but you dont need to do that as the shebang in the west shim does it:

```python title:west_shim.py
#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pyelftools",
#     "PyYAML",
#     "pykwalify",
#     "jsonschema",
#     "canopen",
#     "packaging",
#     "patool",
#     "psutil",
#     "pylink-square",
#     "pyserial",
#     "requests",
#     "semver",
#     "tqdm",
#     "reuse",
#     "anytree",
#     "intelhex",
#     "west",
# ]
# ///

import subprocess  # noqa: S404
import sys
from pathlib import Path

from west.configuration import Configuration
from west.util import WestNotFound, west_topdir


def run_west_cmd(
    west_cmd: list[str],
    zephyr_base: Path | None = None,
) -> None:
    if zephyr_base and zephyr_base.is_dir():
        requirements_txt_path = zephyr_base / "scripts" / "requirements-base.txt"

        cmd = [
            "uvx",
            "--with-requirements",
            str(requirements_txt_path),
            "west",
            *west_cmd,
        ]
    else:
        cmd = ["uvx", "west", *west_cmd]

    try:
        res = subprocess.run(
            cmd,
            check=True,
        )
        if res.stdout:
            print(
                f"""
        {res.stdout.decode().rstrip()}
                            """,
            )

    except subprocess.CalledProcessError as exc:
        print(f"""
                    process failed!
                        cmd: {exc.cmd}
                        retcode: {exc.returncode}
                        stderr: {exc.stderr.rstrip().decode()}
                        build_output:
                        stdout: {exc.stdout.rstrip().decode()}
                        """)

        sys.exit(1)


def main():
    west_args = sys.argv[1:]
    zephyr_base = None
    try:
        if topdir := west_topdir(None, fall_back=True):
            westconfig = Configuration(topdir)
            if zephyr_base_val := westconfig.get("zephyr.base", f"{topdir}/zephyr"):
                zephyr_base = Path(zephyr_base_val)
    except WestNotFound:
        print("No west workspace found, are you inside a workspace?")

    run_west_cmd(west_args, zephyr_base)


if __name__ == "__main__":
    main()
```

The script only concerns itself with running the uvx command (short for `uv tool run`) with the rest of the dependencies that the Zephyr repo has and passes on all the arguments to west as normal.

The west shim itself only prepends its own directory (and uv) to `PATH`; the
toolchain env vars come from whichever toolchain variant tool you have active
(see [Multiple toolchain variants](#multiple-toolchain-variants) above).

## Usage

```bash
# Install the plugin
mise plugin install zephyr-sdk https://github.com/ale-alfaro/vfox-zephyr-sdk

# List available versions
mise ls-remote zephyr-sdk:arm-zephyr-eabi

# Install a specific version of the arm-zephyr-eabi toolchain
mise install zephyr-sdk:arm-zephyr-eabi@0.17.0
# Install a specific version of west
mise install zephyr-sdk:west@0.17.0

# Use on demand (doesn't make changes to your PATH)
mise x zephyr-sdk:west@0.17.0 -- west build -p -b native_sim app

# Use as your default west installation
mise use zephyr-sdk:west@0.17.0
# It will prepend the shim to your path
west build -p -b native_sim app

```

## Environment variables

Which variables are set depends on the selected variant:

| Variable                    | `zephyr` / `llvm` variant                                              | `gnuarmemb` variant                          |
| --------------------------- | --------------------------------------------------------------------- | -------------------------------------------- |
| `ZEPHYR_TOOLCHAIN_VARIANT`  | `zephyr` or `llvm`                                                     | `gnuarmemb`                                  |
| `ZEPHYR_SDK_INSTALL_DIR`    | `<install>` (SDK root Zephyr searches under)                          | _not set_                                    |
| `GNUARMEMB_TOOLCHAIN_PATH`  | _not set_                                                             | `<install>` (toolchain root, holds `bin/`)   |
| `PATH` (toolchains)         | `<toolchain>/bin` (`gnu/<toolchain>/bin` for SDK >= 1.0.0; `llvm/bin` for llvm) | `<install>/bin`                    |

The generic `{VARIANT}_TOOLCHAIN_PATH` pointer is only needed for out-of-tree
variants like `gnuarmemb`; the `zephyr` and `llvm` toolchains ship inside the
SDK and are located via `ZEPHYR_SDK_INSTALL_DIR`.

Other tools also set:

| Variable             | Value                                     |
| -------------------- | ----------------------------------------- |
| `PATH` (minimal SDK) | adds `setup.sh` installer                 |
| `PATH` (west shim)   | adds a copy of the `west_shim.py` as west |

## Development

### Local testing

```bash
mise plugin link --force zephyr-sdk-test .
mise cache clear
mise install zephyr-sdk:arm-zephyr-eabi@0.17.0
mise install zephyr-sdk:west@0.17.0
mise x zephyr-sdk:west@0.17.0 -- west --version
```

### Code quality

```bash
mise run lint       # Run all linters
mise run format     # Format Lua code
mise run test # Full CI suite
mise run ci         # Full CI suite
```

### Debugging

Adds debug and trace logs to the plugin:

```bash
mise plugin link --force zephyr-sdk-test .
mise cache clear
MISE_DEBUG=1 mise install zephyr-sdk-test:west@0.17.0
```

## Files

- `metadata.lua` - Plugin metadata
- `hooks/backend_list_versions.lua` - Lists available versions from GitHub releases
- `hooks/backend_install.lua` - Downloads and installs the SDK (minimal SDK + toolchains via setup.sh)
- `hooks/backend_exec_env.lua` - Configures PATH, ZEPHYR_SDK_INSTALL_DIR, ZEPHYR_TOOLCHAIN_VARIANT
- `lib/` - Shared library for GitHub API, platform detection, asset resolution
- `mise-tasks/smoke-test` - Quick install and verify test
- `mise-tasks/integration-test` - Full Zephyr build test

## License

MIT
