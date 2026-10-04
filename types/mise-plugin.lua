--- LuaCATS type definitions for mise vfox plugins
--- These annotations provide IDE support via lua-language-server.
--- See https://luals.github.io/wiki/annotations/

------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------

---@class Runtime
---@field osType string Operating system type (e.g. "linux", "darwin", "windows")
---@field archType string Architecture type (e.g. "amd64", "arm64")
---@field envType string|nil libc environment type ("gnu" on glibc Linux, "musl" on musl Linux, nil on other platforms)
---@field version string Runtime version
---@field pluginDirPath string Path to the plugin directory
RUNTIME = {}

--- @deprecated Use RUNTIME.osType instead
---@type string
OS_TYPE = ""

--- @deprecated Use RUNTIME.archType instead
---@type string
ARCH_TYPE = ""

------------------------------------------------------------------------
-- PLUGIN table & hook method signatures
------------------------------------------------------------------------


---@class PreInstallCtx
---@field args string[] Command-line arguments
---@field version string Requested version

---@class PostInstallCtx
---@field rootPath string Installation root path
---@field runtimeVersion string Runtime version
---@field sdkInfo table<string, SdkInfo> SDK info for installed versions
---@field options table Tool options from mise.toml

---@class SdkInfo
---@field path string Installation path
---@field version string Installed version
---@field note? string Optional note

---@class EnvKey
---@field key string Environment variable name
---@field value string Environment variable value

---@class BackendListToolsCtx

---@class BackendTool
---@field name string Name of tool
---@field description string?  Description of tool


---@class BackendToolsResponse
---@field tools BackendTool[] List of available tools

---@class BackendListToolsCtx

---@class BackendListToolsResult : BackendToolsResponse

---@class BackendSearchToolsCtx
---@field query string Search string to look tools with

---@class BackendSearchToolsResult : BackendToolsResponse
---
---@class BackendListVersionsCtx
---@field tool string Tool name

---@class BackendListVersionsResult
---@field versions string[] List of available versions

---@class BackendInstallCtx
---@field tool string Tool name
---@field version string Version to install
---@field install_path string Path where the tool should be installed
---@field download_path string Path where the tool artifact should be downloaded
---@field options table<string, any> Tool options from the current config

---@class BackendInstallResult

---@class BackendExecEnvCtx
---@field tool string Tool name
---@field version string Installed version
---@field install_path string Installation path
---@field options table<string, any> Tool options from the current config

---@class BackendExecEnvResult
---@field env_vars EnvKey[] Environment variables to set

---@class BackendUninstallCtx
---@field tool string Tool name
---@field version string Installed version
---@field install_path string Installation path, still present when the hook runs
---@field download_path string Download path
---@field options table<string, any> Tool options from the current config

---@class Plugin
---@field name string Plugin name
---@field BackendListTools? fun(self: Plugin, ctx: BackendListToolsCtx): BackendListToolsResult
---@field BackendSearchTools? fun(self: Plugin, ctx: BackendSearchToolsCtx): BackendSearchToolsResult
---@field BackendListVersions? fun(self: Plugin, ctx: BackendListVersionsCtx): BackendListVersionsResult
---@field BackendListVersions? fun(self: Plugin, ctx: BackendListVersionsCtx): BackendListVersionsResult
---@field BackendInstall? fun(self: Plugin, ctx: BackendInstallCtx): BackendInstallResult
---@field BackendExecEnv? fun(self: Plugin, ctx: BackendExecEnvCtx): BackendExecEnvResult
---@field BackendUninstall? fun(self: Plugin, ctx: BackendUninstallCtx)
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
---@field get fun(opts: HttpRequestOpts): HttpResponse Send a GET request
---@field head fun(opts: HttpRequestOpts): HttpResponse Send a HEAD request (no body)
---@field download_file fun(opts: HttpRequestOpts, path: string) Download a file to disk
local http = {}

-- json module --------------------------------------------------------

---@class json
---@field encode fun(value: any): string Encode a value as JSON
---@field decode fun(str: string): any Decode a JSON string
local json = {}

-- file module --------------------------------------------------------

---@class FileStat
---@field size integer File size in bytes
---@field is_file boolean Whether this is a regular file
---@field is_dir boolean Whether this is a directory
---@field is_symlink boolean Whether this is a symlink
---@field modified integer|nil Last modification time (Unix seconds since epoch, nil if unavailable)
---@field accessed integer|nil Last access time (Unix seconds since epoch, nil if unavailable)
---@field created integer|nil Creation time (Unix seconds since epoch, nil if unavailable)
---@field mode string|nil Octal permission mode string (Unix only, e.g. "755", nil on Windows)

---@class file
---@field read fun(path: string): string Read file contents
---@field exists fun(path: string): boolean Check if a file exists
---@field symlink fun(src: string, dst: string) Create a symbolic link
---@field join_path fun(...: string): string Join path components
---@field stat fun(path: string): FileStat|nil Get file metadata or nil if not found
---@field list fun(path: string): string[] List immediate directory entries in sorted order
---@field glob fun(pattern: string): string[] List paths matching a glob pattern in sorted order
---@field move fun(src: string, dst: string) Move a file or directory
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

---@class ArchiverDecompressOpts
---@field strip_components? integer Flatten top-level directories while retaining root files (0 or 1)

---@class archiver
---@field decompress fun(archive: string, dest: string, opts?: ArchiverDecompressOpts) Decompress an archive (.zip, .tar.gz, .tar.xz, .tar.bz2)
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
