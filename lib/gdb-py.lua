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

local GITHUB_REPO = "zephyrproject-rtos/binutils-gdb"
local BRANCH_PREFIX = "zephyr-gdb-"
local PY_VER = "3.12.15"
local DEFAULT_TARGET = "arm-zephyr-eabi"
local STORE_KEY = "zephyr_gdb_branches"

--- Versions are the `zephyr-gdb-<ver>` branches of the zephyr binutils-gdb fork.
local fetch_branches = function() ---@as AssetBundleFetchFn
    local request = Utils.net.gh_api(GITHUB_REPO, "branches?per_page=100", { reqType = "GET" })
    local branches = Utils.net.get_json_payload(request, function(branch)
        return type(branch.name) == "string" and Utils.strings.has_prefix(branch.name, BRANCH_PREFIX)
    end) or {}
    local bundles = {} ---@as table<Version, ToolchainBundle>
    for _, branch in ipairs(branches) do
        local version = branch.name:sub(#BRANCH_PREFIX + 1)
        bundles[version] = {
            asset_name = branch.name,
            version = version,
            download_url = string.format(
                "https://github.com/%s/archive/refs/heads/%s.tar.gz",
                GITHUB_REPO,
                branch.name
            ),
        }
    end
    return bundles
end

---@param ctx BackendListVersionsCtx
---@return string[] versions
M.list_versions = function(ctx)
    Utils.validate_ctx(ctx, "list-versions")
    return Utils.store.fetch_versions(STORE_KEY, fetch_branches)
end

---@param ctx BackendInstallCtx
function M.install(ctx)
    Utils.validate_ctx(ctx, "install")
    if Utils.os() ~= "linux" then
        Utils.fatal("gdb-py is only built on Linux hosts", { os = Utils.os() })
    end
    local opts = ctx.options or {}
    local version, prefix, work = ctx.version, ctx.install_path, ctx.download_path
    local target = opts.target or DEFAULT_TARGET
    local asset = Utils.store.fetch_toolchain_asset(STORE_KEY, fetch_branches, version)
    if not asset then
        Utils.fatal("No " .. BRANCH_PREFIX .. "<version> branch for this version", { version = version })
    end

    -- Python: uv installs into <dir>/cpython-<ver>-linux-<arch>-gnu, flattened to <prefix>/python.
    local py = Utils.fs.join_path(prefix, "python")
    local uv_dir = Utils.fs.join_path(work, "uv")
    Utils.inf("Installing CPython with uv", { version = PY_VER })
    Utils.sh.exec(
        { "uv", "python", "install", PY_VER, "--install-dir", uv_dir, "--no-bin" },
        { fail = true, timeout = 600 }
    )
    Utils.file.move(Utils.fs.join_path(uv_dir, "cpython-" .. PY_VER .. "-linux-" .. Utils.arch() .. "-gnu"), py)

    -- GDB sources: branch tarball unpacks as binutils-gdb-<branch>/.
    Utils.inf("Downloading GDB sources", { branch = asset.asset_name })
    local src_root = Utils.net.archived_asset_download(asset.download_url, work, work, { name = "src" })
        or Utils.fatal("Failed to download GDB sources", { url = asset.download_url })
    ---@cast src_root string
    local src = Utils.fs.join_path(src_root, "binutils-gdb-" .. asset.asset_name)

    -- Build. Env goes through `env` so $ORIGIN never meets make or shell quoting.
    local build = Utils.fs.join_path(work, "build")
    Utils.sh.mkdir(build)
    local jobs = tostring(opts.jobs or Utils.sh.exec({ "nproc" }) or 1)
    local env = {
        "env",
        "CC=gcc",
        "CXX=g++",
        "CFLAGS=-O2",
        "CXXFLAGS=-O2",
        "LDFLAGS=-L" .. py .. "/lib",
        "LD_RUN_PATH='$ORIGIN/../python/lib'",
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
        "--with-pkgversion='vfox-zephyr-sdk gdb-py'",
    })
    Utils.inf("Building GDB", { jobs = jobs })
    run({ "make", "-j" .. jobs, "MAKEINFO=true", "all-gdb" })
    run({ "make", "MAKEINFO=true", "install-gdb" })

    -- The bundled interpreter must be the one gdb boots.
    local gdb = Utils.fs.join_path(prefix, "bin", target .. "-gdb-py")
    local got = Utils.sh.exec(
        { gdb, "--nx", "--batch", "-ex", "'python import sys; print(sys.prefix)'" },
        { fail = true, timeout = 60 }
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
    return {
        { key = "PATH", value = Utils.fs.join_path(ctx.install_path, "bin") },
    }
end

return M
