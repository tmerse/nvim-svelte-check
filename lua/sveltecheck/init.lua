-- Compatibility layer for v1.x to v2.x migration
-- do not edit, just leave as is and we will eventually delete
local M = {}

vim.notify_once(
	"Warning: The 'sveltecheck' module has been renamed to 'svelte-check'. Please update your config. See https://github.com/nvim-svelte/nvim-svelte-check for migration guide.",
	vim.log.levels.WARN
)

-- Forward all calls to the new module
setmetatable(M, {
	__index = function(_, key)
		local ok, module = pcall(require, "svelte-check")
		if ok and module then
			return module[key]
		end
		-- Fallback in case the new module isn't available
		return nil
	end,
})

return M
