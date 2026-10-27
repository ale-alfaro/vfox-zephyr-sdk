# zephyr-sdk

## Overview

A [mise](https://mise.jdx.dev/) backend plugin for the [Zephyr SDK](https://github.com/zephyrproject-rtos/sdk-ng) toolchain and other companion tools useful for Zephyr development

- Target specific [Zephyr SDK toolchains](#zephyr-sdk-toolchain) (`arm`,`riscv64`, ... etc) or\
  a generic tool (`toolchain`) that can be customized to have multiple targets\
  and optional host tools using mise tool options
- West (`west`) with all the dependencies included
- GNU ARM Embedded toolchain (`gnuaremb`)
- GDB with python support baked in to the tool instead of using the systems python version (`gdb-py`)

### Zephyr-SDK versions provided and Compatibility matrix with Zephyr Release

The Zepyhr-SDK versions are fetched on-demand from `zephyrproject-rtos/sdk-ng` releases so the versions are always up to date
with what is released officially by Zephyr. However the plugin provides only `0.17.0` version of the toolchain pre 1.0. You should
pick the toolchain according to the version of Zephyr in your workspace. Below summary of the [compatiblity matrix](https://docs.google.com/spreadsheets/d/1wzGJLRuR6urTgnDFUqKk7pEB8O6vWu6Sxziw_KROxMA)

| version | 4.4.0 | 4.3.0 | 4.2.0 | 4.1.0 | 4.0.0 |
| ------- | ----- | ----- | ----- | ----- | ----- |
| 1.0.0+  | Y     | N     | N     | N     | N     |
| 0.17.0  | N     | Y     | Y     | Y     | Y     |

In short if you are using a Zephyr release older than 4.4 use the 0.17.0 toolchain version, otherwise use the 1.0.0 or newer.

---

## Usage

1. Install the plugin.

```sh
> mise plugin add zephyr-sdk https://github.com/ale-alfaro/vfox-zephyr-sdk.git
```

Once installed `zephyr-sdk` should show up as a backend

```sh
> mise plugin ls
zephyr-sdk
```

2. Add a toolchain and west as tools to your mise.local.toml

```sh
touch mise.local.toml
mise --env=local use zephyr-sdk:arm@0.17.0 # arm-zephyr-eabi-* tools
mise --env=local use west # West python package + other required dependencies (`pyelftools`, `intelhex`, ...)
```

3. Build!

```bash
mise exec -- west build -p -b my/awesome/board path/to/your/app
```

---

## Alternative toolchains

### GNU ARM Embedded

```sh
mise use zephyr-sdk:gnuarmemb@15.2.rel1  # ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
```

`gnuarmemb` is managed independently of the Zephyr SDK: its own download source
(Arm), version scheme (e.g. `15.2.rel1`), and install path. Any Arm-published
version works, not just the ones shown by `ls-remote`.

### LLVM (Zephyr v4.4.0+ only!)

Add or update your mise toml file:

```toml
"zephyr-sdk:arm" = { version = "latest", llvm = true }
```

Or if you havent yet installed the tool change the invocation to:

```sh
mise use "zephyr-sdk:arm@1.0.0[llvm=true]"
```

To build with the LLVM toolchain you must specify the `ZEPHYR_TOOLCHAIN_VARIANT` argument as a CMake variable

```bash
mise exec -- west build -p -b my/awesome/board path/to/your/app -- -DZEPHYR_TOOLCHAIN_VARIANT=zephyr/llvm
# OR set it in the west config for your workspace
west config --local build.cmake-args -- -DZEPHYR_TOOLCHAIN_VARIANT=zephyr/llvm
```

### Multiple Toolchains and LLVM

```bash
mise install zephyr-sdk:toolchain@0.17.0[toolchains=arm,riscv64]                       # -> arm-zephyr-eabi and riscv64-zephyr-elf 
mise install zephyr-sdk:toolchain@0.17.0[toolchains=arm,hosttools=true]  # host tools opt in
```
