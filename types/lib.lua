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
---@class ZephyrSdkToolOptions
---@field target table<string,{target_triple:string}> Toolchain passed to `setup.sh -t` (e.g. "arm-zephyr-eabi")
---@field llvm boolean Whether to install the llvm toolchain as part of the ZephyrSDK install 
---@field hosttools? boolean Install host tools

---@class ZephyrTool
---@field list_versions fun(opts?: ToolOptions): string[]
---@field install fun(ctx: BackendInstallCtx): nil
---@field envs fun(ctx: BackendExecEnvCtx): table<string,string>
---@field name string Name
---@field description string Description
---@field options table Options

---@class ReleaseStore
---@field releases? table<Version, table>
---@field timestamp? number
---
---@class WestToolOptions
---@field additional_requirements? table<string, Version>
---
---@alias ToolOptions WestToolOptions|ZephyrSdkToolOptions

------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------

--- LuaCATS type definitions for mise vfox plugins
--- These annotations provide IDE support via lua-language-server.
--- See https://luals.github.io/wiki/annotations/

------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------

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
---@field decompress_strip_components fun(archive_path:string, install_dir:string, root_dir:string):string?
Utils.net = {}

-- json module --------------------------------------------------------


-- file module --------------------------------------------------------


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


---@class utils.CmdExecOpts : CmdExecOpts
---@field fail? boolean If true a failure in the command exec will error out
---@field silent? boolean If true returns no output

---@class cmd
---@field exec fun(command: string, opts?: CmdExecOpts): string Execute a shell command
Utils.cmd = {}

---@class Utils.sh : cmd
---@field exec fun(cmd: string[], opts?: utils.CmdExecOpts):string?
---@field execf fun(opts?: utils.CmdExecOpts,fmt: string, ...):string?
---@field whichdir fun(tool: string): string? Get bin dir for a mise tool
---@field which fun(exe: string): string? Check if command exists in PATH
---@field realpath fun(filepath: string): string? Resolve real path
---@field cwd fun(): string? Get current working directory
---@field mkdir fun(dir: string) Create directory recursively
---@field chmod fun( mode: string,filepath: string) Set file permissions
---@field cp fun( src: string,dst: string, opts?:{recursive:boolean,force:boolean}) Set file permissions
Utils.sh = {}


-- store module -------------------------------------------------------
---@alias AssetBundleFetchFn fun():table<Version,ToolchainBundle>
---@class Utils.store
---@field store_table fun(data: table, store_name: string): string? Write table to JSON store
---@field fetch_versions fun(store_name:string,fetch_fn:AssetBundleFetchFn):string[]
---@field fetch_toolchain_asset fun(store_name:string, fetch_fn:AssetBundleFetchFn, version:string):ToolchainBundle?
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


return nil
