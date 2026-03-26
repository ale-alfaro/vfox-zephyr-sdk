--- LuaCATS type definitions for mise backend plugins
--- These annotations provide IDE support via lua-language-server.
--- See https://luals.github.io/wiki/annotations/

------------------------------------------------------------------------
-- Zephyr SDK specific types
------------------------------------------------------------------------

---@class ZephyrSdkRelease
---@field tag_name string Release tag (e.g. "v0.17.0")
---@field prerelease boolean Whether this is a pre-release
---@field assets ZephyrSdkAsset[] Release assets

---@class ZephyrSdkAsset
---@field name string Asset filename
---@field browser_download_url string Download URL

---@class ZephyrSdkAssetResult
---@field version string Version string (e.g. "0.17.0")
---@field url string Download URL
---@field name string Asset filename

------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------

---@class Runtime
---@field osType string Operating system type (e.g. "linux", "darwin", "windows")
---@field archType string Architecture type (e.g. "amd64", "arm64")
---@field envType? string libc environment type ("gnu" on glibc Linux, "musl" on musl Linux, nil otherwise)
---@field version string Runtime version
---@field pluginDirPath string Path to the plugin directory
RUNTIME = {}

------------------------------------------------------------------------
-- PLUGIN table & hook method signatures
------------------------------------------------------------------------

---@class EnvKey
---@field key string Environment variable name
---@field value string Environment variable value

---@class BackendListVersionsCtx
---@field tool string Tool name

---@class BackendListVersionsResult
---@field versions string[] List of available versions in ascending semver order

---@class BackendInstallCtx
---@field tool string Tool name
---@field version string Version to install
---@field install_path string Path where the tool should be installed
---@field download_path string Temporary download directory
---@field options table Custom options from mise.toml

---@class BackendInstallResult

---@class BackendExecEnvCtx
---@field tool string Tool name
---@field version string Installed version
---@field install_path string Installation path
---@field options table Custom options from mise.toml

---@class BackendExecEnvResult
---@field env_vars EnvKey[] Environment variables to set

---@class MiseEnvCtx
---@field options table Plugin options from mise.toml

---@class MiseEnvResult
---@field env? EnvKey[] Environment variables to set
---@field cacheable? boolean Whether the result can be cached (default false)
---@field watch_files? string[] Files to watch for cache invalidation

---@class MisePathCtx
---@field options table Plugin options from mise.toml

---@class Plugin
---@field name string Plugin name
---@field BackendListVersions? fun(self: Plugin, ctx: BackendListVersionsCtx): BackendListVersionsResult
---@field BackendInstall? fun(self: Plugin, ctx: BackendInstallCtx): BackendInstallResult
---@field BackendExecEnv? fun(self: Plugin, ctx: BackendExecEnvCtx): BackendExecEnvResult
---@field MiseEnv? fun(self: Plugin, ctx: MiseEnvCtx): MiseEnvResult|EnvKey[]
---@field MisePath? fun(self: Plugin, ctx: MisePathCtx): string[]
PLUGIN = {}

------------------------------------------------------------------------
-- Built-in modules (available via require)
------------------------------------------------------------------------

-- http module --------------------------------------------------------

---@class HttpRequestOpts
---@field url string Request URL
---@field headers? table<string, string> HTTP headers

---@class HttpResponse
---@field status_code integer HTTP status code
---@field headers table<string, string> Response headers
---@field body string Response body (only for get, not head)

---@class http
---@field get fun(opts: HttpRequestOpts): HttpResponse, string? Send a GET request
---@field head fun(opts: HttpRequestOpts): HttpResponse, string? Send a HEAD request (no body)
---@field download_file fun(opts: HttpRequestOpts, path: string): string? Download a file to disk
---@field try_get fun(opts: HttpRequestOpts): HttpResponse?, string? Non-raising GET request
---@field try_head fun(opts: HttpRequestOpts): HttpResponse?, string? Non-raising HEAD request
---@field try_download_file fun(opts: HttpRequestOpts, path: string): boolean?, string? Non-raising download
local http = {}

-- json module --------------------------------------------------------

---@class json
---@field encode fun(value: any): string Encode a value as JSON
---@field decode fun(str: string): any Decode a JSON string
local json = {}

-- file module --------------------------------------------------------

---@class file
---@field read fun(path: string): string Read file contents
---@field exists fun(path: string): boolean Check if a file exists
---@field symlink fun(src: string, dst: string) Create a symbolic link
---@field join_path fun(...: string): string Join path components
local file = {}

-- cmd module ---------------------------------------------------------

---@class CmdExecOpts
---@field cwd? string Working directory
---@field env? table<string, string> Environment variables
---@field timeout? integer Timeout in milliseconds

---@class cmd
---@field exec fun(command: string, opts?: CmdExecOpts): string Execute a shell command
local cmd = {}

-- env module ---------------------------------------------------------

---@class env
---@field setenv fun(key: string, val: string) Set an environment variable
---@field getenv fun(key: string): string? Get an environment variable
local env = {}

-- archiver module ----------------------------------------------------

---@class archiver
---@field decompress fun(archive: string, dest: string): string? Decompress an archive (.zip, .tar.gz, .tar.xz, .tar.bz2)
local archiver = {}

-- semver module ------------------------------------------------------

---@class semver
---@field compare fun(v1: string, v2: string): integer Compare two version strings (-1, 0, 1)
---@field parse fun(version: string): integer[] Parse a version string into numeric parts
---@field sort fun(versions: string[]): string[] Sort version strings in ascending order
---@field sort_by fun(arr: table[], field: string): table[] Sort tables by a version field
local semver = {}

-- strings module -----------------------------------------------------

---@class strings
---@field split fun(s: string, sep: string): string[] Split a string by separator
---@field has_prefix fun(s: string, prefix: string): boolean Check if string starts with prefix
---@field has_suffix fun(s: string, suffix: string): boolean Check if string ends with suffix
---@field trim fun(s: string, suffix: string): string Trim suffix from end of string
---@field trim_space fun(s: string): string Trim whitespace from both ends
---@field contains fun(s: string, substr: string): boolean Check if string contains substring
---@field join fun(arr: any[], sep: string): string Join array elements with separator
local strings = {}

-- html module --------------------------------------------------------

---@class HtmlNode
---@field find fun(self: HtmlNode, selector: string): HtmlNode Find descendant nodes matching a CSS selector
---@field first fun(self: HtmlNode): HtmlNode Get the first node
---@field eq fun(self: HtmlNode, idx: integer): HtmlNode Get node at zero-based index
---@field each fun(self: HtmlNode, fn: fun(idx: integer, node: HtmlNode)) Iterate over nodes
---@field text fun(self: HtmlNode): string Get the text content
---@field attr fun(self: HtmlNode, key: string): string Get an attribute value

---@class html
---@field parse fun(html_str: string): HtmlNode Parse an HTML string into a node tree
local html = {}

-- log module ---------------------------------------------------------

---@class log
---@field trace fun(...: any) Log at trace level
---@field debug fun(...: any) Log at debug level
---@field info fun(...: any) Log at info level
---@field warn fun(...: any) Log at warn level
---@field error fun(...: any) Log at error level
local log = {}

return nil
