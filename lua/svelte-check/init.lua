local M = {}

local default_config = {
	command = "pnpm run check",
	spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
	debug_mode = false,
}

local config = vim.deepcopy(default_config)
local spinner_index = 1
local spinner_timer = nil
local summary_info = "No errors or warnings found... nice!" -- Fixed the escape issue
local collected_output = {}

local silent_print = function(msg)
	vim.api.nvim_echo({ { msg, "Normal" } }, false, {})
end

-- Helper function to find the project root
local function find_project_root()
	local current_dir = vim.fn.getcwd()
	while current_dir ~= "/" do
		if vim.fn.glob(current_dir .. "/package.json") ~= "" then
			return current_dir
		end
		current_dir = vim.fn.fnamemodify(current_dir, ":h") -- Move up one directory
	end
	return nil
end

local function start_spinner()
	if spinner_timer then
		spinner_timer:stop()
	end

	spinner_timer = vim.defer_fn(function()
		silent_print("Running Svelte Check... " .. config.spinner_frames[spinner_index])
		spinner_index = (spinner_index % #config.spinner_frames) + 1
		start_spinner()
	end, 100)
end

local function stop_spinner()
	if spinner_timer then
		spinner_timer:stop()
		spinner_timer:close()
		spinner_timer = nil
	end
	vim.o.statusline = ""
	vim.cmd("redrawstatus")
end

-- Capture raw output when debugging is needed
local function save_raw_output()
	if #collected_output == 0 then
		return
	end

	local cache_dir = vim.fn.stdpath("cache")
	local output_file = cache_dir .. "/svelte-check-output.log"

	local file = io.open(output_file, "w")
	if file then
		file:write("--- Svelte Check Raw Output ---\n\n")
		for i, line in ipairs(collected_output) do
			file:write(string.format("[%d] %s\n", i, line))
		end
		file:close()
		print("Raw output saved to: " .. output_file)
		return output_file
	else
		print("Failed to save raw output to log file")
		return nil
	end
end

local function process_output()
	-- Always print the number of lines collected regardless of debug mode
	print("Processing " .. #collected_output .. " lines of svelte-check output")

	if config.debug_mode then
		print("Debug: Detailed processing of collected output")
	end

	local quickfix_list = {}
	local error_count = 0
	local warning_count = 0
	local file_count = 0

	for i, line in ipairs(collected_output) do
		if config.debug_mode then
			print("Processing line " .. i .. ": " .. line)
		end

		-- First check if this is a valid machine format output line
		local timestamp = line:match("^%d+")
		if not timestamp then
			if config.debug_mode then
				print("Skipped non-epoch line: " .. line)
			end
			goto continue
		end

		-- Check for completion summary
		if line:match("COMPLETED") then
			local stats_pattern = "^%d+%s+COMPLETED%s+(%d+)%s+FILES%s+(%d+)%s+ERRORS%s+(%d+)%s+WARNINGS%s+(%d+)"
			local f, e, w = line:match(stats_pattern)

			-- Fix type conversion issues by ensuring values are integers
			if f and e and w then
				f = tonumber(f) or 0
				e = tonumber(e) or 0
				w = tonumber(w) or 0

				file_count = f
				error_count = e
				warning_count = w

				if config.debug_mode then
					print(
						"Found stats: "
							.. file_count
							.. " files, "
							.. error_count
							.. " errors, "
							.. warning_count
							.. " warnings"
					)
				end
			else
				if config.debug_mode then
					print("Could not extract all stats from COMPLETED line: " .. line)
				end
			end
			goto continue
		end

		-- Check for errors and warnings - fixed pattern for svelte-check machine format
		if line:match("ERROR") or line:match("WARNING") then
			-- Format example: 1744219831987 ERROR "src/routes/file.svelte" 45:21 "Error message."
			local error_type, file_path, line_col, description =
				line:match('^%d+%s+(%a+)%s+"([^"]+)"%s+(%d+:%d+)%s+"(.-)"')

			if error_type and file_path and line_col and description then
				local line_number, column_number = line_col:match("(%d+):(%d+)")

				if line_number and column_number then
					local lnum = tonumber(line_number) or 0
					local col = tonumber(column_number) or 0

					table.insert(quickfix_list, {
						filename = file_path,
						lnum = lnum,
						col = col,
						text = description,
						type = error_type:sub(1, 1), -- E for Error, W for Warning
						nr = 0,
						valid = true,
					})

					if config.debug_mode then
						print(
							"Added quickfix entry: "
								.. error_type
								.. " in "
								.. file_path
								.. " at "
								.. lnum
								.. ":"
								.. col
						)
					end
				else
					if config.debug_mode then
						print("Failed to parse line:col from: " .. line_col)
					end
				end
			else
				if config.debug_mode then
					print("No match found with primary pattern for line: " .. line)
				end

				-- Try alternate pattern without quotes around the message
				error_type, file_path, line_col, description = line:match('^%d+%s+(%a+)%s+"([^"]+)"%s+(%d+:%d+)%s+(.*)')

				if error_type and file_path and line_col and description then
					local line_number, column_number = line_col:match("(%d+):(%d+)")

					if line_number and column_number then
						local lnum = tonumber(line_number) or 0
						local col = tonumber(column_number) or 0

						-- Remove quotes if they exist
						description = description:gsub('^"', ""):gsub('"$', "")

						table.insert(quickfix_list, {
							filename = file_path,
							lnum = lnum,
							col = col,
							text = description,
							type = error_type:sub(1, 1),
							nr = 0,
							valid = true,
						})

						if config.debug_mode then
							print("Added quickfix entry (alt pattern): " .. error_type .. " in " .. file_path)
						end
					end
				else
					if config.debug_mode then
						print("No match found with alternate pattern for line: " .. line)
					end
				end
			end
		end

		::continue::
	end

	-- Update summary based on collected statistics or quickfix entries
	if error_count > 0 or warning_count > 0 or #quickfix_list > 0 then
		if error_count > 0 or warning_count > 0 then
			summary_info = "Svelte Check completed with "
				.. error_count
				.. " errors and "
				.. warning_count
				.. " warnings in "
				.. file_count
				.. " files."
		else
			-- Fallback if we have quickfix entries but no summary stats
			local qf_errors = 0
			local qf_warnings = 0
			for _, item in ipairs(quickfix_list) do
				if item.type == "E" then
					qf_errors = qf_errors + 1
				elseif item.type == "W" then
					qf_warnings = qf_warnings + 1
				end
			end
			summary_info = "Svelte Check completed with " .. qf_errors .. " errors and " .. qf_warnings .. " warnings."
		end
	else
		summary_info = "No errors or warnings found... nice!"
	end

	if #quickfix_list > 0 then
		vim.fn.setqflist({}, "r", { title = "Svelte Check", items = quickfix_list })
		vim.cmd("copen")
		print("Opened quickfix list with " .. #quickfix_list .. " issues")
	else
		vim.fn.setqflist({}, "r", { title = "Svelte Check", items = {} })
	end

	return #quickfix_list > 0
end

M.run = function()
	start_spinner()
	collected_output = {}

	-- Find the project root directory
	local project_root = find_project_root()
	if not project_root then
		print("Could not find project root with package.json. Running in the current directory.")
		project_root = vim.fn.getcwd() -- Fallback to the current directory
	end

	-- If debug mode is on, test if the command is available
	if config.debug_mode then
		local test_cmd = "cd " .. vim.fn.shellescape(project_root) .. " && " .. config.command .. " --help"
		print("Testing command: " .. test_cmd)
		local sys_output = vim.fn.system(test_cmd)
		local sys_exit_code = vim.v.shell_error
		print("Test command exit code: " .. sys_exit_code)
		if sys_output then
			print("Test command output sample: " .. string.sub(sys_output, 1, 100))
		end
	end

	if config.debug_mode then
		print("Running command in directory: " .. project_root)
	end

	-- Use an array for command arguments to avoid shell parsing issues
	local cmd_parts = vim.split(config.command, " ")
	local final_command = cmd_parts[1]
	local cmd_args = {}
	for i = 2, #cmd_parts do
		table.insert(cmd_args, cmd_parts[i])
	end
	table.insert(cmd_args, "--output")
	table.insert(cmd_args, "machine")

	if config.debug_mode then
		print("Command parts:", vim.inspect(cmd_parts))
		print("Final command:", final_command)
		print("Command args:", vim.inspect(cmd_args))
	end

	local final_command_str = config.command .. " --output machine"

	if config.debug_mode then
		print("Running command string: " .. final_command_str)
	end

	-- Use jobstart with proper shell settings
	local job_id = vim.fn.jobstart(final_command_str, {
		cwd = project_root, -- Run the command in the project root directory
		stdout_buffered = false, -- Process output line by line
		stderr_buffered = false,
		shell = true, -- Execute with shell to ensure PATH is properly loaded
		on_stdout = function(_, data)
			if data and #data > 0 then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(collected_output, line)
						if config.debug_mode then
							print("Received output: " .. line)
						end
					end
				end
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						-- Also collect stderr output to help with diagnostics
						table.insert(collected_output, "STDERR: " .. line)
						-- Always log stderr output regardless of debug mode
						print("stderr: " .. line)

						-- Check for common error patterns
						if line:match("ERR_PNPM_NO_SCRIPT") or line:match('Command "[^"]+" not found') then
							print("Command not found: " .. config.command)
							print("Try using 'npx svelte-check' as your command instead of 'pnpm run check'")
							print("You can change the command by adding to your Neovim config:")
							print("require('svelte-check').setup({ command = 'npx svelte-check' })")
						end
					end
				end
			end
		end,
		on_exit = function(_, exit_code)
			stop_spinner()

			local has_errors = process_output()

			print(summary_info)

			-- Exit code 1 is expected when errors are found
			if exit_code == 1 and has_errors then
			-- Normal behavior: command found errors (exit code 1) and we parsed them correctly
			elseif exit_code > 1 then
				print("Svelte Check failed with exit code " .. exit_code)
				if not config.debug_mode then
					-- Automatically save raw output on failure when debug is off
					save_raw_output()
				end
			elseif exit_code == 1 and not has_errors then
				print(
					"Svelte Check exited with code 1 but no errors were captured. This might indicate a parsing issue."
				)
				if not config.debug_mode then
					-- Save raw output when we get exit code 1 but no errors parsed
					save_raw_output()
					print("Try running with debug_mode = true to see more details")
				end
			end

			if config.debug_mode then
				save_raw_output()
			end
		end,
	})

	if job_id <= 0 then
		stop_spinner()
		print("Failed to start Svelte Check process!")
	end
end

function M.setup(user_config)
	if user_config then
		config = vim.tbl_deep_extend("force", config, user_config)
	end

	-- Try to automatically detect the best command to use for svelte-check
	if not user_config or not user_config.command then
		-- Check if any of the potential commands exist
		local project_root = find_project_root() or vim.fn.getcwd()
		local cmd_options = {
			"pnpm run check", -- Default in the plugin
			"npm run check",
			"yarn run check",
			"npx svelte-check", -- Direct execution
		}

		local found_command = nil
		for _, cmd in ipairs(cmd_options) do
			local base_cmd = cmd:match("^(%S+)")
			if vim.fn.executable(base_cmd) == 1 then
				-- If pnpm/npm/yarn, check if check script exists
				if base_cmd == "pnpm" or base_cmd == "npm" or base_cmd == "yarn" then
					vim.fn.system(
						"cd " .. vim.fn.shellescape(project_root) .. " && " .. base_cmd .. " run | grep -q check"
					)
					local exit_code = vim.v.shell_error
					if exit_code == 0 then
						found_command = cmd
						break
					end
				else
					-- For npx, just check if it exists
					found_command = cmd
					break
				end
			end
		end

		if found_command and found_command ~= config.command then
			if config.debug_mode then
				print("Automatically selecting svelte-check command: " .. found_command)
			end
			config.command = found_command
		end
	end

	vim.api.nvim_create_user_command("SvelteCheck", function()
		M.run()
	end, { desc = "Run `svelte-check` asynchronously and load the results into a qflist", force = true })
end

return M
