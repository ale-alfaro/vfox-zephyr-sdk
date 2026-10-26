--- Relocatable `<target>-gdb-py` built from zephyrproject-rtos/binutils-gdb
--- with its own CPython (uv-managed python-build-standalone) under
--- `<install_path>/python`. Both `--with-python` paths sit under `--prefix`, so
--- GDB resolves its Python libdir relative to the binary, and LD_RUN_PATH gives
--- libpython an `$ORIGIN` rpath. No crosstool-ng, no system Python.
---
--- Linux only. Host needs gcc/g++, make, bison, flex, uv and the gmp, mpfr,
--- expat and ncurses dev packages (what a gcc install already pulls in).
---@class ZephyrTool
local M = {}

-- Only the newest `zephyr-gdb-<ver>` branch of the zephyr binutils-gdb fork is supported.
local VERSION = "16.2"
local BRANCH = "zephyr-gdb-" .. VERSION
local SRC_URL = "https://github.com/zephyrproject-rtos/binutils-gdb/archive/refs/heads/" .. BRANCH .. ".tar.gz"
local PY_VER = "3.12.15"
local DEFAULT_TARGET = "arm-zephyr-eabi"

---@return string[] versions
M.list_versions = function ()
    return { VERSION }
end

--- The branch carries no release date; the build recipe here is what changes, so date by its last commit.
M.release_dates = function ()
    return Utils.source_dates({ VERSION }, "lib/gdb-py.lua")
end

---@param ctx BackendInstallCtx
function M.install(ctx)
    Utils.validate_ctx(ctx, "install")
    if Utils.os() ~= "linux" then
        Utils.fatal("gdb-py is only built on Linux hosts", { os = Utils.os() })
    end
    local opts = ctx.options or {}
    local prefix, work = ctx.install_path, ctx.download_path
    local target = opts.target or DEFAULT_TARGET
    if ctx.version ~= VERSION then
        Utils.fatal("gdb-py only supports version " .. VERSION, { version = ctx.version })
    end

    -- Python: uv installs into <dir>/cpython-<ver>-linux-<arch>-gnu, flattened to <prefix>/python.
    local py = Utils.fs.join_path(prefix, "python")
    local uv_dir = Utils.fs.join_path(work, "uv")
    Utils.inf("Installing CPython with uv", { version = PY_VER })
    Utils.sh.exec(
        { "uv", "python", "install", PY_VER, "--install-dir", uv_dir, "--no-bin" }, { fail = true, timeout = 600 }
    )
    Utils.file.move(Utils.fs.join_path(uv_dir, "cpython-" .. PY_VER .. "-linux-" .. Utils.arch() .. "-gnu"), py)

    -- GDB sources: branch tarball unpacks as binutils-gdb-<branch>/.
    Utils.inf("Downloading GDB sources", { branch = BRANCH })
    local src_root = Utils.net.archived_asset_download(SRC_URL, work, work, { name = "src" })
        or Utils.fatal("Failed to download GDB sources", { url = SRC_URL })
    ---@cast src_root string
    local src = Utils.fs.join_path(src_root, "binutils-gdb-" .. BRANCH)

    -- Build. Env goes through `env` so $ORIGIN never meets make or shell quoting.
    local build = Utils.fs.join_path(work, "build")
    Utils.sh.mkdir(build)
    local jobs = tostring(opts.jobs or Utils.sh.exec({ "nproc" }) or 1)
    local env = {
        "env", "CC=gcc", "CXX=g++", "CFLAGS=-O2", "CXXFLAGS=-O2", "LDFLAGS=-L" .. py .. "/lib",
        "LD_RUN_PATH='$ORIGIN/../python/lib'"
    }
    local function run(args)
        Utils.sh.exec(Utils.list_extend(Utils.list_extend({}, env), args), { fail = true, cwd = build, timeout = 3600 })
    end
    Utils.inf("Configuring GDB", { target = target, prefix = prefix })
    run({
        Utils.fs.join_path(src, "configure"),
        "--target=" .. target,
        "--prefix=" .. prefix,
        "--program-prefix=" .. target .. "-",
        "--program-suffix=-py",
        "--disable-binutils",
        "--disable-gas",
        "--disable-ld",
        "--disable-gprof",
        "--disable-gdbserver",
        "--disable-sim",
        "--disable-nls",
        "--disable-werror",
        "--disable-source-highlight",
        "--with-static-standard-libraries",
        "--without-guile",
        "--without-lzma",
        "--without-zstd",
        "--without-debuginfod",
        "--without-xxhash",
        "--with-expat",
        "--with-python=" .. Utils.fs.join_path(py, "bin", "python3"),
        "--with-python-libdir=" .. Utils.fs.join_path(py, "lib"),
        "--with-pkgversion='vfox-zephyr-sdk gdb-py'"
    })
    Utils.inf("Building GDB", { jobs = jobs })
    run({ "make", "-j" .. jobs, "MAKEINFO=true", "all-gdb" })
    run({ "make", "MAKEINFO=true", "install-gdb" })

    -- The bundled interpreter must be the one gdb boots.
    local gdb = Utils.fs.join_path(prefix, "bin", target .. "-gdb-py")
    local got = Utils.sh.exec(
        { gdb, "--nx", "--batch", "-ex", "'python import sys; print(sys.prefix)'" }, { fail = true, timeout = 60 }
    )
    if got ~= py then
        Utils.fatal("gdb-py did not boot its bundled Python", { expected = py, got = got })
    end
    Utils.inf("Installed gdb-py", { gdb = gdb })
end

---@param ctx BackendExecEnvCtx
---@return EnvKey[]
function M.envs(ctx)
    Utils.validate_ctx(ctx, "exec")
    return { { key = "PATH", value = Utils.fs.join_path(ctx.install_path, "bin") } }
end

return M
