-- git-oil.nvim - Git status integration for oil.nvim
-- https://github.com/smiggiddy/git-oil.nvim
-- Based on oil-git.nvim by Ben O'Mahony (https://github.com/benomahony/oil-git.nvim)
-- Licensed under MIT

local M = {}

-- Plugin enabled state
M.enabled = true

-- Default highlight colors (only used if not already defined)
local default_highlights = {
	OilGitAdded = { fg = "#a6e3a1" },
	OilGitModified = { fg = "#f9e2af" },
	OilGitRenamed = { fg = "#cba6f7" },
	OilGitDeleted = { fg = "#f38ba8" },
	OilGitUntracked = { fg = "#89b4fa" },
	OilGitConflict = { fg = "#f38ba8", bold = true },
	OilGitStagedModified = { fg = "#a6e3a1" },
	OilGitUnstagedModified = { fg = "#f9e2af" },
	OilGitPartiallyStaged = { fg = "#fab387" },
	OilGitStagedDeleted = { fg = "#a6e3a1" },
	OilGitUnstagedDeleted = { fg = "#f38ba8" },
}

-- Default symbols for git status indicators
local default_symbols = {
	added = "+",
	modified = "~",
	renamed = "→",
	deleted = "✗",
	untracked = "?",
	conflict = "!",
	staged = "●",
	unstaged = "○",
	partially_staged = "±",
}

-- Cache for git status results
local status_cache = {}
local cache_timeout = 2000 -- 2 seconds
local debounce_delay = 200 -- milliseconds
local debounce_timer = nil
local symbols = vim.deepcopy(default_symbols)
local show_directory_status = true

-- Track pending async requests to avoid duplicate calls
local pending_requests = {}

-- Check if async git status is available (Neovim 0.10+)
local has_async = vim.fn.has("nvim-0.10") == 1

-- Priority order for status codes (higher = more important)
local status_priority = {
	conflict = 6,
	partially_staged = 5,
	modified = 4,
	added = 3,
	renamed = 2,
	deleted = 2,
	untracked = 1,
}

-- Map status codes to priority categories
local function get_status_priority(status_code)
	if not status_code then
		return 0
	end

	local first_char = status_code:sub(1, 1)
	local second_char = status_code:sub(2, 2)

	-- Conflicts
	if status_code == "UU" or status_code == "AA" or status_code == "DD"
		or status_code == "AU" or status_code == "UA"
		or status_code == "DU" or status_code == "UD" then
		return status_priority.conflict
	end

	-- Partially staged
	if status_code == "MM" or status_code == "MD" or status_code == "AM" or status_code == "AD" then
		return status_priority.partially_staged
	end

	-- Modified (staged or unstaged)
	if first_char == "M" or second_char == "M" then
		return status_priority.modified
	end

	-- Added
	if first_char == "A" then
		return status_priority.added
	end

	-- Renamed
	if first_char == "R" then
		return status_priority.renamed
	end

	-- Deleted
	if first_char == "D" or second_char == "D" then
		return status_priority.deleted
	end

	-- Untracked
	if status_code == "??" then
		return status_priority.untracked
	end

	return 0
end

-- Propagate file status to parent directories
local function propagate_directory_status(file_status, git_root)
	if not show_directory_status then
		return file_status
	end

	local dir_status = {}

	for filepath, status_code in pairs(file_status) do
		-- Walk up the directory tree from the file to the git root
		local parent = vim.fn.fnamemodify(filepath, ":h")

		while parent and parent ~= git_root and #parent > #git_root do
			-- Ensure the path ends with / for directory matching
			local dir_path = parent:sub(-1) == "/" and parent or parent .. "/"

			local current_priority = get_status_priority(dir_status[dir_path])
			local new_priority = get_status_priority(status_code)

			-- Keep the higher priority status
			if new_priority > current_priority then
				dir_status[dir_path] = status_code
			end

			-- Move to parent directory
			parent = vim.fn.fnamemodify(parent, ":h")
		end
	end

	-- Merge directory status with file status
	return vim.tbl_extend("keep", file_status, dir_status)
end

local function setup_highlights()
	-- Only set highlight if it doesn't already exist (respects colorscheme)
	for name, opts in pairs(default_highlights) do
		if vim.fn.hlexists(name) == 0 then
			vim.api.nvim_set_hl(0, name, opts)
		end
	end
end

local function get_git_root(path)
	local git_dir = vim.fn.finddir(".git", path .. ";")
	if git_dir == "" then
		return nil
	end
	-- Get the parent directory of .git, not .git itself
	return vim.fn.fnamemodify(git_dir, ":p:h:h")
end

-- Parse git status output into a status table
local function parse_git_status_output(output, git_root)
	local status = {}
	for line in output:gmatch("[^\r\n]+") do
		if #line >= 3 then
			local status_code = line:sub(1, 2)
			local filepath = line:sub(4)

			-- Handle renames (format: "old-name -> new-name")
			if status_code:sub(1, 1) == "R" then
				local arrow_pos = filepath:find(" %-> ")
				if arrow_pos then
					filepath = filepath:sub(arrow_pos + 4)
				end
			end

			-- Remove leading "./" if present
			if filepath:sub(1, 2) == "./" then
				filepath = filepath:sub(3)
			end

			-- Convert to absolute path
			local abs_path = git_root .. "/" .. filepath

			status[abs_path] = status_code
		end
	end

	-- Propagate status to parent directories
	return propagate_directory_status(status, git_root)
end

-- Synchronous git status (fallback for Neovim < 0.10)
local function get_git_status_sync(dir)
	local git_root = get_git_root(dir)
	if not git_root then
		return {}
	end

	-- Check cache
	local now = vim.loop.now()
	local cached = status_cache[git_root]
	if cached and (now - cached.timestamp) < cache_timeout then
		return cached.status
	end

	local cmd = string.format("cd %s && git status --porcelain", vim.fn.shellescape(git_root))
	local output = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		return {}
	end

	local status = parse_git_status_output(output, git_root)

	-- Cache the result
	status_cache[git_root] = {
		status = status,
		timestamp = now,
	}

	return status
end

-- Async git status (Neovim 0.10+)
local function get_git_status_async(dir, callback)
	local git_root = get_git_root(dir)
	if not git_root then
		callback({})
		return
	end

	-- Check cache
	local now = vim.loop.now()
	local cached = status_cache[git_root]
	if cached and (now - cached.timestamp) < cache_timeout then
		callback(cached.status)
		return
	end

	-- Check if there's already a pending request for this git root
	if pending_requests[git_root] then
		-- Add callback to pending request
		table.insert(pending_requests[git_root], callback)
		return
	end

	-- Start a new pending request
	pending_requests[git_root] = { callback }

	vim.system(
		{ "git", "-C", git_root, "status", "--porcelain" },
		{ text = true },
		function(result)
			vim.schedule(function()
				local status = {}
				if result.code == 0 and result.stdout then
					status = parse_git_status_output(result.stdout, git_root)

					-- Cache the result
					status_cache[git_root] = {
						status = status,
						timestamp = vim.loop.now(),
					}
				end

				-- Call all pending callbacks
				local callbacks = pending_requests[git_root] or {}
				pending_requests[git_root] = nil

				for _, cb in ipairs(callbacks) do
					cb(status)
				end
			end)
		end
	)
end

-- Get git status (uses async when available)
local function get_git_status(dir, callback)
	if has_async and callback then
		get_git_status_async(dir, callback)
	else
		return get_git_status_sync(dir)
	end
end

local function get_highlight_group(status_code)
	if not status_code then
		return nil, nil
	end

	local first_char = status_code:sub(1, 1)
	local second_char = status_code:sub(2, 2)

	-- Check for merge conflicts first (highest priority)
	-- UU = both modified, AA = both added, DD = both deleted
	-- AU/UA = added by us/them, DU/UD = deleted by us/them
	if status_code == "UU" or status_code == "AA" or status_code == "DD"
		or status_code == "AU" or status_code == "UA"
		or status_code == "DU" or status_code == "UD" then
		return "OilGitConflict", symbols.conflict
	end

	-- Check for partially staged files (both staged and unstaged changes)
	if status_code == "MM" or status_code == "MD" or status_code == "AM" or status_code == "AD" then
		return "OilGitPartiallyStaged", symbols.partially_staged
	end

	-- Untracked files
	if status_code == "??" then
		return "OilGitUntracked", symbols.untracked
	end

	-- Staged additions (A followed by space or M)
	if first_char == "A" and second_char == " " then
		return "OilGitAdded", symbols.added
	end

	-- Staged modifications (M followed by space)
	if first_char == "M" and second_char == " " then
		return "OilGitStagedModified", symbols.staged
	end

	-- Unstaged modifications (space followed by M)
	if first_char == " " and second_char == "M" then
		return "OilGitUnstagedModified", symbols.unstaged
	end

	-- Renamed files (staged)
	if first_char == "R" then
		return "OilGitRenamed", symbols.renamed
	end

	-- Staged deletions (D followed by space)
	if first_char == "D" and second_char == " " then
		return "OilGitStagedDeleted", symbols.staged
	end

	-- Unstaged deletions (space followed by D)
	if first_char == " " and second_char == "D" then
		return "OilGitUnstagedDeleted", symbols.unstaged
	end

	return nil, nil
end

local function clear_highlights(bufnr)
	bufnr = bufnr or 0
	local ns_id = vim.api.nvim_create_namespace("oil_git_status")
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Apply highlights to current buffer given git status
local function apply_highlights_to_buffer(git_status, current_dir, target_bufnr)
	local oil = require("oil")
	local bufnr = target_bufnr or vim.api.nvim_get_current_buf()

	-- Verify buffer is still valid and is an oil buffer
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "oil" then
		return
	end

	-- Verify we're still in the same directory (for async calls)
	local new_dir = oil.get_current_dir(bufnr)
	if new_dir ~= current_dir then
		return
	end

	local ns_id = vim.api.nvim_create_namespace("oil_git_status")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Clear existing highlights for this buffer
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	for i, line in ipairs(lines) do
		local entry = oil.get_entry_on_line(bufnr, i)
		if entry and (entry.type == "file" or entry.type == "directory") then
			local filepath
			if entry.type == "file" then
				filepath = current_dir .. entry.name
			else
				-- Directories use trailing slash for matching
				filepath = current_dir .. entry.name .. "/"
			end

			local status_code = git_status[filepath]
			local hl_group, symbol = get_highlight_group(status_code)

			if hl_group and symbol then
				-- Find the entry name part in the line and highlight it
				local name_start = line:find(entry.name, 1, true)
				if name_start then
					-- Single extmark for both text highlight and virtual text symbol
					vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, name_start - 1, {
						end_col = name_start - 1 + #entry.name,
						hl_group = hl_group,
						virt_text = { { " " .. symbol, hl_group } },
						virt_text_pos = "eol",
					})
				end
			end
		end
	end
end

local function apply_git_highlights()
	-- Skip if plugin is disabled
	if not M.enabled then
		clear_highlights()
		return
	end

	local oil = require("oil")
	local bufnr = vim.api.nvim_get_current_buf()
	local current_dir = oil.get_current_dir(bufnr)

	if not current_dir then
		clear_highlights(bufnr)
		return
	end

	if has_async then
		-- Use async version - capture buffer ID for callback
		get_git_status(current_dir, function(git_status)
			if vim.tbl_isempty(git_status) then
				clear_highlights(bufnr)
				return
			end
			apply_highlights_to_buffer(git_status, current_dir, bufnr)
		end)
	else
		-- Use sync version
		local git_status = get_git_status(current_dir)
		if vim.tbl_isempty(git_status) then
			clear_highlights(bufnr)
			return
		end
		apply_highlights_to_buffer(git_status, current_dir, bufnr)
	end
end

-- Debounced version for frequent events
local function apply_git_highlights_debounced()
	if debounce_timer then
		debounce_timer:stop()
	end
	debounce_timer = vim.defer_fn(apply_git_highlights, debounce_delay)
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("OilGitStatus", { clear = true })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = "oil://*",
		callback = function()
			vim.schedule(apply_git_highlights)
		end,
	})

	-- Clear highlights when leaving oil buffers
	vim.api.nvim_create_autocmd("BufLeave", {
		group = group,
		pattern = "oil://*",
		callback = clear_highlights,
	})

	-- Use debounced version for rapid-fire events
	vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "oil://*",
		callback = function()
			vim.schedule(apply_git_highlights_debounced)
		end,
	})

	-- Use debounced version for focus events
	vim.api.nvim_create_autocmd({ "FocusGained", "WinEnter", "BufWinEnter" }, {
		group = group,
		pattern = "oil://*",
		callback = function()
			vim.schedule(apply_git_highlights_debounced)
		end,
	})

	-- Terminal events (for when lazygit closes) - invalidate cache
	vim.api.nvim_create_autocmd("TermClose", {
		group = group,
		callback = function()
			-- Invalidate cache when terminal closes
			status_cache = {}
			vim.schedule(function()
				if vim.bo.filetype == "oil" then
					apply_git_highlights()
				end
			end)
		end,
	})

	-- Also catch common git-related user events - invalidate cache
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "FugitiveChanged", "GitSignsUpdate", "LazyGitClosed" },
		callback = function()
			-- Invalidate cache on git events
			status_cache = {}
			if vim.bo.filetype == "oil" then
				vim.schedule(apply_git_highlights)
			end
		end,
	})
end

-- Track if plugin has been initialized
local initialized = false

local function initialize()
	if initialized then
		return
	end

	setup_highlights()
	setup_autocmds()
	initialized = true
end

function M.setup(opts)
	opts = opts or {}

	-- Merge user highlights with defaults (only affects fallbacks)
	if opts.highlights then
		default_highlights = vim.tbl_extend("force", default_highlights, opts.highlights)
	end

	-- Allow customizing cache timeout
	if opts.cache_timeout then
		cache_timeout = opts.cache_timeout
	end

	-- Allow customizing debounce delay
	if opts.debounce_delay then
		debounce_delay = opts.debounce_delay
	end

	-- Allow customizing symbols
	if opts.symbols then
		symbols = vim.tbl_extend("force", symbols, opts.symbols)
	end

	-- Allow disabling directory status propagation
	if opts.show_directory_status ~= nil then
		show_directory_status = opts.show_directory_status
	end

	-- Allow starting disabled
	if opts.enabled ~= nil then
		M.enabled = opts.enabled
	end

	initialize()
end

-- Auto-initialize when oil buffer is entered (if not already done)
vim.api.nvim_create_autocmd("FileType", {
	pattern = "oil",
	callback = function()
		initialize()
	end,
	group = vim.api.nvim_create_augroup("OilGitAutoInit", { clear = true }),
})

-- Manual refresh function (also invalidates cache)
function M.refresh()
	status_cache = {}
	apply_git_highlights()
end

-- Clear highlights from all oil buffers
local function clear_all_oil_highlights()
	local ns_id = vim.api.nvim_create_namespace("oil_git_status")
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "oil" then
			vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
		end
	end
end

-- Enable the plugin
function M.enable()
	M.enabled = true
	M.refresh()
end

-- Disable the plugin
function M.disable()
	M.enabled = false
	clear_all_oil_highlights()
end

-- Toggle the plugin
function M.toggle()
	if M.enabled then
		M.disable()
	else
		M.enable()
	end
end

return M
