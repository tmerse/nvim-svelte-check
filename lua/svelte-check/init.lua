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

	-- Always print the first few lines to help debugging
	print("First few lines of collected output:")
	for i = 1, math.min(5, #collected_output) do
		print(string.format("[%d] %s", i, collected_output[i]))
	end

	local quickfix_list = {}
	local error_count = 0
	local warning_count = 0
	local file_count = 0

	for i, line in ipairs(collected_output) do
		-- First check if this is a valid machine format output line
		local timestamp = line:match("^%d+")
		if not timestamp then
			-- Skip non-timestamp lines
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

				print(
					"Found stats: "
						.. file_count
						.. " files, "
						.. error_count
						.. " errors, "
						.. warning_count
						.. " warnings"
				)
			else
				print("Could not extract all stats from COMPLETED line: " .. line)
			end
			goto continue
		end

		-- Check for errors and warnings using multiple approaches
		if line:match("ERROR") or line:match("WARNING") then
			print("Processing potential error/warning line: " .. line)

			-- Try different patterns

			-- Pattern 1: Standard quotes format
			local error_type, file_path, line_col, description =
				line:match('^%d+%s+(%a+)%s+"([^"]+)"%s+(%d+:%d+)%s+"(.-)"')

			if error_type and file_path and line_col and description then
				print("Pattern 1 matched!")
			else
				print("Pattern 1 did not match, trying pattern 2...")
				-- Pattern 2: Without quotes around description
				error_type, file_path, line_col, description = line:match('^%d+%s+(%a+)%s+"([^"]+)"%s+(%d+:%d+)%s+(.*)')
			end

			if not (error_type and file_path and line_col) then
				print("Pattern 2 did not match, trying pattern 3...")
				-- Pattern 3: More permissive
				error_type, file_path, line_col, description = line:match('(%a+)%s+"([^"]+)"%s+(%d+:%d+)')

				if error_type and file_path and line_col then
					description = line:match(line_col .. "%s+(.+)$") or "Unknown error"
				end
			end

			if error_type and file_path and line_col then
				local line_number, column_number = line_col:match("(%d+):(%d+)")

				if line_number and column_number then
					local lnum = tonumber(line_number) or 0
					local col = tonumber(column_number) or 0

					-- Clean up description if needed
					if description then
						description = description:gsub('^"', ""):gsub('"$', "")
					else
						description = "Unknown error"
					end

					table.insert(quickfix_list, {
						filename = file_path,
						lnum = lnum,
						col = col,
						text = description,
						type = error_type:sub(1, 1), -- E for Error, W for Warning
						nr = 0,
						valid = true,
					})

					print("Added quickfix entry: " .. error_type .. " in " .. file_path .. " at " .. lnum .. ":" .. col)
				else
					print("Failed to parse line:col from: " .. line_col)
				end
			else
				print("No pattern matched for line: " .. line)

				-- Extra fallback for typical svelte-check format
				if line:match("ERROR") or line:match("WARNING") then
					local parts = {}
					for part in line:gmatch("%S+") do
						table.insert(parts, part)
					end

					if #parts >= 4 then
						-- Expected format might be: TIMESTAMP ERROR "FILE" LINE:COL "MESSAGE"
						local error_type = parts[2]
						local file_path = parts[3]:gsub('^"', ""):gsub('"$', "")
						local line_col = parts[4]

						if line_col:match("%d+:%d+") then
							local line_number, column_number = line_col:match("(%d+):(%d+)")
							local lnum = tonumber(line_number) or 0
							local col = tonumber(column_number) or 0

							-- Reconstruct message from remaining parts
							local msg = ""
							for i = 5, #parts do
								msg = msg .. " " .. parts[i]
							end
							msg = msg:gsub('^%s+"', ""):gsub('"$', "")

							table.insert(quickfix_list, {
								filename = file_path,
								lnum = lnum,
								col = col,
								text = msg or "Unknown error",
								type = error_type:sub(1, 1),
								nr = 0,
								valid = true,
							})

							print("Added quickfix entry using fallback: " .. error_type .. " in " .. file_path)
						end
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

	print("Found " .. #quickfix_list .. " issues to add to quickfix list")

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

	print("Running svelte-check in: " .. project_root)

	local final_command_str = config.command .. " --output machine"
	print("Running command: " .. final_command_str)

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
			print("svelte-check completed with exit code: " .. exit_code)
			local has_errors = process_output()

			print(summary_info)

			-- Exit code 1 is expected when errors are found
			if exit_code == 1 and has_errors then
				-- Normal behavior: command found errors (exit code 1) and we parsed them correctly
				print("Successfully parsed errors/warnings")
			elseif exit_code > 1 then
				print("Svelte Check failed with exit code " .. exit_code)
				save_raw_output()
			elseif exit_code == 1 and not has_errors then
				print(
					"Svelte Check exited with code 1 but no errors were captured. This might indicate a parsing issue."
				)
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
			print("Automatically selecting svelte-check command: " .. found_command)
			config.command = found_command
		end
	end

	vim.api.nvim_create_user_command("SvelteCheck", function()
		M.run()
	end, { desc = "Run `svelte-check` asynchronously and load the results into a qflist", force = true })
end

return M
