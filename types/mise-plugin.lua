--- LuaCATS type definitions for mise backend plugins
--- These annotations provide IDE support via lua-language-server.
--- See https://luals.github.io/wiki/annotations/
---@meta
------------------------------------------------------------------------
-- Zephyr SDK specific types
------------------------------------------------------------------------

---@alias ZephyrSdkOsType
---| '"linux"'
---| '"darwin"'
---| '"windows"'
---
---@alias ZephyrSdkArchType
---| '"amd64"'
---| '"arm64"'
---
---
---@alias Version string
---
---@alias ZephyrSdkToolchainFamily
---| '"zephyr"'
---| '"ncs"'
---| '"llvm"'
---
---@class ToolchainOptions
---@field toolchains? string[] Toolchain targets to install (e.g. {"arm-zephyr-eabi"})
---@field hosttools? boolean Install host tools
---@field cmake_pkg? boolean Register Zephyr SDK CMake package
---@field family? ZephyrSdkToolchainFamily
---
---@class ToolchainBundle
---@field asset_name string
---@field version string
---@field checksum string
---@field download_url string

---
---@class ZephyrSdkAsset : ToolchainBundle
---@field github_asset_url string

---@alias AssetMap table<ZephyrSdkOsType, table<ZephyrSdkArchType, ZephyrSdkAsset>> Release assets
---@class ZephyrSdkRelease
---@field tag_name string Release tag (e.g. "v0.17.0")
---@field minimal_assets AssetMap
---
---@class ZephyrTool
---@field list_versions fun(): string[]
---@field install fun(ctx: BackendInstallCtx): nil
---@field envs fun(ctx: BackendExecEnvCtx): table<string,string>

---@class ReleaseStore
---@field releases? table<Version, table>
---@field timestamp? number
---
---@class WestToolOptions
---@field additional_requirements? table<string, Version>
---@field ncs? boolean
---
---@alias ToolOptions WestToolOptions|ToolchainOptions

---@class ZephyrTool
---@field list_versions? fun(): string[]
---@field install fun(ctx:BackendInstallCtx, override?:ToolOptions):BackendInstallResult
---@field envs fun(ctx:BackendExecEnvCtx, override?:ToolOptions):EnvKey[]

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
---@field options? ToolchainOptions|WestToolOptions Custom options from mise.toml

---@class BackendExecEnvResult
---@field env_vars EnvKey[] Environment variables to set

---@class MiseEnvCtx
---@field options? ToolchainOptions|WestToolOptions Custom options from mise.toml

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

--- @alias MergeTableBehaviorPolicy
---|'error'  raise an error
---|'keep'   use value from the leftmost map
---|'force'  use value from the rightmost map

---@comment If a function, it receives the current key, the previous value in the currently merged table (if present), the current value and should
---return the value for the given key in the merged table.
---@alias MergeTableBehavior MergeTableBehavior|fun(key:any, prev_value:any?, value:any):any
---      - "error": raise an error
---      - "keep":  use value from the leftmost map
---      - "force": use value from the rightmost map
---      - If a function, it receives the current key, the previous value
---        in the currently merged table (if present), the current value and should
---        return the value for the given key in the merged table.
---@alias FileExtensionType
---| 'archive'
---| 'executable'

------------------------------------------------------------------------
-- Built-in modules (available via require)
------------------------------------------------------------------------
---@generic K,V
---@alias MappingFn fun(mapping:(fun(value:V):any),tabl:table<K,V>):table<K,any>
---
---@class Utils
--- Submodules (mise built-in, loaded lazily via __index)
---@field strings strings
---@field semver semver
---@field file file
---@field http Utils.http
---@field cmd cmd
---@field json json
--- Submodules (custom, loaded lazily via __index)
---@field fs Utils.fs
---@field sh Utils.sh
---@field net Utils.net
---@field store Utils.store
---@field inspect fun(root: any, options?: table): string
--- Core utility functions
---@field inf fun(...: any) Log at info level
---@field wrn fun(...: any) Log at warn level
---@field err fun(...: any) Log at error level
---@field dbg fun(...: any) Log at debug level
---@field islist fun(t: table): boolean
---@field ensure_list fun(t: any|any[]):any[]
---@field list_extend fun(dst: table, src:table,start:integer?,finish:integer?):table
---@field tbl_extend fun(behavior: MergeTableBehavior, ...: table<any,any>): table
---@field tbl_map MappingFn
---@field tbl_deep_extend fun(behavior: MergeTableBehavior, ...: table<any,any>): table
---@field platform_create_string fun(template:string, opts?:{exttype?:FileExtensionType,override?:table}):string
Utils = {}
-- http module --------------------------------------------------------

---@class HttpRequestOpts
---@field url string Request URL
---@field headers? table<string, string> HTTP headers

---@class HttpResponse
---@field status_code integer HTTP status code
---@field headers table<string, string> Response headers
---@field body string Response body (only for get, not head)

---@class Utils.http
---@field get fun(opts: HttpRequestOpts): HttpResponse, string? Send a GET request
---@field head fun(opts: HttpRequestOpts): HttpResponse, string? Send a HEAD request (no body)
---@field download_file fun(opts: HttpRequestOpts, path: string): string? Download a file to disk
---@field try_get fun(opts: HttpRequestOpts): HttpResponse?, string? Non-raising GET request
---@field try_head fun(opts: HttpRequestOpts): HttpResponse?, string? Non-raising HEAD request
---@field try_download_file fun(opts: HttpRequestOpts, path: string): boolean?, string? Non-raising download
Utils.http = {}

-- net module (extends http) ------------------------------------------

---@alias GhApiRequestType
---| 'GET'
---| 'DOWNLOAD'
---
---@class GhApiOpts
---@field reqType GhApiRequestType
---@field token? string
---
---@class GhListReleasesPayload
---@field name string
---@field tag_name string
---@field draft boolean
---@field prerelease boolean
---
---@class ReleasesConstraints
---@field version? {min:Version,max:Version}
---@field prereleases?  boolean
---
---@class GithubReleasesConstraints : ReleasesConstraints
---@field drafts? boolean

---@class Utils.net : Utils.http
---@field platform_create_string fun(template: string, exttype?: string): string Substitute platform placeholders
---@field github_asset_download fun(repo: string, asset_id: string, install_path: string, download_path: string): string Download GitHub release asset
---@field gh_api fun(repo: string, components:string, opts?:GhApiOpts): HttpRequestOpts
---@field archived_asset_download fun(url: string, install_dir: string, download_dir: string, asset_opts?: table): string? Download and extract archive
---@field executable_asset_download fun(url: string, install_dir: string, exe_name?: string): string? Download executable
---@field get_json_payload fun(request: string|HttpRequestOpts, filter_fn?: function, key_to_filter?: string): table? Fetch and parse JSON
---@field decompress_strip_components fun(install_dir:string ,archive_path:string,components:number):string?
Utils.net = {}

-- json module --------------------------------------------------------

---@class json
---@field encode fun(value: any): string Encode a value as JSON
---@field decode fun(str: string): any Decode a JSON string
Utils.json = {}

-- file module --------------------------------------------------------

---@class file
---@field read fun(path: string): string Read file contents
---@field exists fun(path: string): boolean Check if a file exists
---@field symlink fun(src: string, dst: string) Create a symbolic link
---@field join_path fun(...: string): string Join path components
---
---

---@class Utils.fs : file
---@field parents fun(start: string): fun(): string? Walk up directory tree
---@field isdir fun(path: string): boolean
---@field isabspath fun(path: string): boolean
---@field directory_exists fun(path: string): boolean Check if directory exists
---@field scandir fun(directory: string, opts?: ScanDirOpts): string[] List files in directory
---@field basename fun(file: string): string Get filename from path
---@field dirname fun(file: string): string Get parent directory from path
---@field path_exists fun(path: string, opts?: PathExistsOpts): boolean Check path existence
---@field normalize fun(path:string,opts?:Utils.fs.normalize.Opts):string  Normalized path
---@field abspath fun(path: string): string Convert to absolute path
---@field relpath fun(base: string,target:string): string Convert to relative path
Utils.fs = {}

-- cmd module ---------------------------------------------------------

---@class CmdExecOpts
---@field cwd? string Working directory
---@field env? table<string, string> Environment variables
---@field timeout? integer Timeout in milliseconds

---@class utils.CmdExecOpts : CmdExecOpts
---@field fail? boolean If true a failure in the command exec will error out
---@field silent? boolean If true returns no output

---@class cmd
---@field exec fun(command: string, opts?: CmdExecOpts): string Execute a shell command

---@class Utils.sh : cmd
---@field exec fun(cmd: string[], opts?: utils.CmdExecOpts):string?
---@field execf fun(opts?: utils.CmdExecOpts,fmt: string, ...):string?
---@field whichdir fun(tool: string): string? Get bin dir for a mise tool
---@field which fun(exe: string): string? Check if command exists in PATH
---@field realpath fun(filepath: string): string? Resolve real path
---@field cwd fun(): string? Get current working directory
---@field mkdir fun(dir: string) Create directory recursively
---@field chmod fun( mode: string,filepath: string) Set file permissions
Utils.sh = {}

-- env module ---------------------------------------------------------

---@class env
---@field setenv fun(key: string, val: string) Set an environment variable
local env = {}

-- archiver module ----------------------------------------------------

---@class archiver
---@field decompress fun(archive: string, dest: string): string? Decompress an archive (.zip, .tar.gz, .tar.xz, .tar.bz2)
local archiver = {}

-- store module -------------------------------------------------------
---@alias AssetBundleFetchFn fun():table<Version,ToolchainBundle>
---@class Utils.store
---@field store_exists fun(store_name: string): boolean Check if JSON store exists
---@field store_table fun(data: table, store_name: string): string? Write table to JSON store
---@field read_table fun(store_name: string): table? Read table from JSON store
---@field fetch_versions fun(store_name:string,fetch_fn:AssetBundleFetchFn):string[]?
---@field fetch_asset_bundles fun(store_name:string,version:string):ToolchainBundle?
Utils.store = {}

-- semver module ------------------------------------------------------

---@class semver
---@field compare fun(v1: string, v2: string): integer Compare two version strings (-1, 0, 1)
---@field parse fun(version: string): integer[] Parse a version string into numeric parts
---@field sort fun(versions: string[]): string[] Sort version strings in ascending order
---@field sort_by fun(arr: table[], field: string): table[] Sort tables by a version field
---@field check_version fun(version: string,constraints:ReleasesConstraints):boolean
---@field spairs fun(t: table):[(fun(table: table, index?:number):Version,any),table]
Utils.semver = {}

-- strings module -----------------------------------------------------

---@class strings
---@field split fun(s: string, sep: string): string[] Split a string by separator
---@field has_prefix fun(s: string, prefix: string): boolean Check if string starts with prefix
---@field has_suffix fun(s: string, suffix: string): boolean Check if string ends with suffix
---@field trim fun(s: string, suffix: string): string Trim suffix from end of string
---@field trim_space fun(s: string): string Trim whitespace from both ends
---@field contains fun(s: string, substr: string): boolean Check if string contains substring
---@field join fun(arr: any[], sep: string): string Join array elements with separator
Utils.strings = {}

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
