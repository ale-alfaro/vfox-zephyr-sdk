
--- @param _ctx BackendListToolsCtx
--- @return BackendListToolsResult
function PLUGIN:BackendListTools(_ctx)
	return {
		tools = {
			{ name = "zephyr-sdk", description = "The Zephyr SDK toolchain as a single tool installation" },
			{ name = "gnuarmemb", description = "The ARM GNU Embedded toolchain compatible with most Zephyr installations" },
			{ name = "west" , description = "West - Zephyr's meta tool for working in workspaces" },
		},
	}
end
