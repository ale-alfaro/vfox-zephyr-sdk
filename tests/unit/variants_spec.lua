-- Unit tests for the toolchain-variant logic (llvm, gnuarmemb, and the
-- zephyr-sdk default target). Pure Lua 5.1 / LuaJIT: it stubs the mise-provided
-- globals (Utils, RUNTIME) and captures side effects (download URL, setup.sh
-- command), so it runs offline with no mise, no network and no real installs.
--
-- Run with:  lua tests/unit/variants_spec.lua   (or luajit)

-- Resolve lib/ relative to this file so it works from any CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*[/\\])") or "./"
package.path = this_dir .. "../../lib/?.lua;" .. package.path

------------------------------------------------------------------------
-- Stubbed mise environment
------------------------------------------------------------------------
local captured = { downloads = {}, setups = {} }

local function ver_parts(v)
    local t = {}
    for n in tostring(v):gmatch("%d+") do
        t[#t + 1] = tonumber(n)
    end
    return t
end
local function ver_cmp(a, b)
    local pa, pb = ver_parts(a), ver_parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

RUNTIME = { osType = "linux", archType = "amd64", pluginDirPath = "." }

Utils = {
    validate = function() end,
    inf = function() end,
    dbg = function() end,
    wrn = function() end,
    err = function() end,
    fatal = function(msg)
        error("FATAL:" .. tostring(msg))
    end,
    os = function()
        return ({ darwin = "macos", linux = "linux", windows = "windows" })[RUNTIME.osType:lower()]
    end,
    arch = function()
        return ({ amd64 = "x86_64", arm64 = "aarch64", x86_64 = "x86_64", aarch64 = "aarch64" })[RUNTIME.archType]
    end,
    tbl_extend = function(_behavior, ...)
        local ret = {}
        for i = 1, select("#", ...) do
            local t = select(i, ...)
            if t then
                for k, v in pairs(t) do
                    ret[k] = v
                end
            end
        end
        return ret
    end,
    list_filter = function(fn, t)
        local r = {}
        for _, v in ipairs(t) do
            if fn(v) then
                r[#r + 1] = v
            end
        end
        return r
    end,
    semver = { compare = ver_cmp },
    fs = {
        join_path = function(...)
            -- keep the URL scheme intact, collapse other double slashes
            return (table.concat({ ... }, "/"):gsub("([^:])//+", "%1/"))
        end,
        path_exists = function()
            return true
        end,
    },
    sh = {
        chmod = function() end,
        exec = function(cmd)
            table.insert(captured.setups, table.concat(cmd, " "))
            return "ok"
        end,
    },
    net = {
        archived_asset_download = function(url, install, _dl, opts)
            table.insert(captured.downloads, { url = url, install = install, name = opts and opts.name })
            return install
        end,
    },
    store = {
        fetch_versions = function()
            return { "0.17.0", "0.17.4", "1.0.0", "1.1.0" }
        end,
        fetch_toolchain_asset = function()
            return { download_url = "http://example/a.tar.xz" }
        end,
    },
}

------------------------------------------------------------------------
-- Tiny test harness
------------------------------------------------------------------------
local failures, count = 0, 0
local function check(name, ok, detail)
    count = count + 1
    if ok then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end
local function eq(name, got, want)
    check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want))
end
local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end
local function env_get(env_vars, key)
    -- returns the last value set for key (PATH may repeat), or nil
    local found
    for _, kv in ipairs(env_vars) do
        if kv.key == key then
            found = kv.value
        end
    end
    return found
end
local function has_key(env_vars, key)
    return env_get(env_vars, key) ~= nil
end

local toolchain = require("toolchain")
local llvm = require("llvm")
local gnuarmemb = require("gnuarmemb")

------------------------------------------------------------------------
-- gnuarmemb
------------------------------------------------------------------------
local gv = gnuarmemb.list_versions()
eq("gnuarmemb: newest listed version is 15.2.rel1", gv[1], "15.2.rel1")
check("gnuarmemb: 14.2.rel1 still listed", contains(gv, "14.2.rel1"))

captured.downloads = {}
RUNTIME.osType, RUNTIME.archType = "linux", "amd64"
gnuarmemb.install({ version = "15.2.rel1", install_path = "/opt/g", download_path = "/dl" }, nil)
eq(
    "gnuarmemb: linux/x86_64 15.2 download URL",
    captured.downloads[1].url,
    "https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/"
        .. "arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-eabi.tar.xz"
)

captured.downloads = {}
RUNTIME.osType, RUNTIME.archType = "windows", "amd64"
gnuarmemb.install({ version = "14.2.rel1", install_path = "/opt/g", download_path = "/dl" }, nil)
local win_url = captured.downloads[1].url
check("gnuarmemb: windows uses .zip + mingw host", win_url:match("mingw%-w64%-i686%-arm%-none%-eabi%.zip$") ~= nil)
RUNTIME.osType, RUNTIME.archType = "linux", "amd64"

local ge = gnuarmemb.envs({ install_path = "/opt/g" }, nil)
eq("gnuarmemb: ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb", env_get(ge, "ZEPHYR_TOOLCHAIN_VARIANT"), "gnuarmemb")
eq("gnuarmemb: GNUARMEMB_TOOLCHAIN_PATH is install root", env_get(ge, "GNUARMEMB_TOOLCHAIN_PATH"), "/opt/g")
eq("gnuarmemb: PATH is <root>/bin", env_get(ge, "PATH"), "/opt/g/bin")
check("gnuarmemb: does NOT set ZEPHYR_SDK_INSTALL_DIR", not has_key(ge, "ZEPHYR_SDK_INSTALL_DIR"))

------------------------------------------------------------------------
-- llvm (standalone, no options)
------------------------------------------------------------------------
local lv = llvm.list_versions()
check("llvm: excludes SDK < 1.0.0", not contains(lv, "0.17.0") and not contains(lv, "0.17.4"))
check("llvm: includes SDK >= 1.0.0", contains(lv, "1.0.0") and contains(lv, "1.1.0"))

local le = llvm.envs({ version = "1.0.0", install_path = "/sdk" })
eq("llvm: ZEPHYR_TOOLCHAIN_VARIANT=llvm", env_get(le, "ZEPHYR_TOOLCHAIN_VARIANT"), "llvm")
eq("llvm: ZEPHYR_SDK_INSTALL_DIR set", env_get(le, "ZEPHYR_SDK_INSTALL_DIR"), "/sdk")
eq("llvm: PATH is <sdk>/llvm/bin", env_get(le, "PATH"), "/sdk/llvm/bin")

-- install is gated to SDK >= 1.0.0
local ok_guard = pcall(function()
    llvm.install({ version = "0.17.0", install_path = "/sdk", download_path = "/dl" })
end)
check("llvm: install rejects SDK < 1.0.0", not ok_guard)

-- install ignores any tool options and never adds -h/-c
captured.setups = {}
llvm.install({
    version = "1.0.0",
    install_path = "/sdk",
    download_path = "/dl",
    options = { hosttools = true, cmake_pkg = true },
})
local llvm_cmd = captured.setups[1] or ""
check("llvm: install does not enable host tools", not llvm_cmd:match(" %-h"))
check("llvm: install does not register cmake package", not llvm_cmd:match(" %-c"))

------------------------------------------------------------------------
-- zephyr-sdk (GNU) default target
------------------------------------------------------------------------
captured.setups = {}
toolchain.install({ version = "0.17.0", install_path = "/sdk", download_path = "/dl" }, {})
local base_cmd = captured.setups[1] or ""
check("zephyr-sdk: bare install selects arm-zephyr-eabi", base_cmd:match("arm%-zephyr%-eabi") ~= nil)
check("zephyr-sdk: bare install has no host tools", not base_cmd:match(" %-h"))
check("zephyr-sdk: bare install has no cmake package", not base_cmd:match(" %-c"))

local ze = toolchain.envs({ version = "0.17.0", install_path = "/sdk" }, {})
eq("zephyr-sdk: ZEPHYR_TOOLCHAIN_VARIANT=zephyr", env_get(ze, "ZEPHYR_TOOLCHAIN_VARIANT"), "zephyr")
eq("zephyr-sdk: default PATH points at arm-zephyr-eabi bin", env_get(ze, "PATH"), "/sdk/arm-zephyr-eabi/bin")

------------------------------------------------------------------------
print(string.format("\n%d checks, %d fail: %s", count, failures, failures == 0 and "PASS" or "FAIL"))
os.exit(failures == 0 and 0 or 1)
