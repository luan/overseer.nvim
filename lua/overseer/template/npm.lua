local files = require("overseer.files")
local overseer = require("overseer")

local lockfiles = {
  npm = "package-lock.json",
  pnpm = "pnpm-lock.yaml",
  yarn = "yarn.lock",
}

---@type overseer.TemplateDefinition
local tmpl = {
  priority = 60,
  params = {
    args = { optional = true, type = "list", delimiter = " " },
    cwd = { optional = true },
    use_yarn = {
      deprecated = true,
      desc = "DEPRECATED: use 'bin' instead",
      optional = true,
      type = "boolean",
    },
    bin = { optional = true, type = "string" },
  },
  builder = function(params)
    local fallback = params.use_yarn and "yarn" or "npm"
    local bin = params.bin or fallback
    local cmd = { bin }
    if params.args then
      cmd = vim.list_extend(cmd, params.args)
    end
    return {
      cmd = cmd,
      cwd = params.cwd,
    }
  end,
}

local function get_package_file(opts)
  local filename = vim.fn.findfile("package.json", opts.dir .. ";")
  if filename ~= "" then
    filename = vim.fn.fnamemodify(filename, ":p")
  end
  return filename
end

local function pick_package_manager(opts)
  for mgr, lockfile in pairs(lockfiles) do
    if files.exists(files.join(opts.dir, lockfile)) then
      return mgr
    end
  end
  return "npm"
end

return {
  cache_key = function(opts)
    return get_package_file(opts)
  end,
  condition = {
    callback = function(opts)
      local package_manager = pick_package_manager(opts)
      if not vim.fn.executable(package_manager) then
        return false, string.format("Could not find command '%s'", package_manager)
      end
      if get_package_file(opts) == "" then
        return false, "No package.json file found"
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local package = get_package_file(opts)
    local bin = pick_package_manager(opts)
    local data = files.load_json_file(package)
    local ret = {}
    if data.scripts then
      for k in pairs(data.scripts) do
        table.insert(
          ret,
          overseer.wrap_template(
            tmpl,
            { name = string.format("%s %s", bin, k) },
            { args = { "run", k }, bin = bin }
          )
        )
      end
    end

    -- Load tasks from workspaces
    if data.workspaces then
      for _, workspace in ipairs(data.workspaces) do
        local workspace_path = files.join(vim.fn.fnamemodify(package, ":h"), workspace)
        local workspace_package_file = files.join(workspace_path, "package.json")
        local workspace_data = files.load_json_file(workspace_package_file)
        if workspace_data and workspace_data.scripts then
          for k in pairs(workspace_data.scripts) do
            table.insert(
              ret,
              overseer.wrap_template(
                tmpl,
                { name = string.format("%s[%s] %s", bin, workspace, k) },
                { args = { "run", k }, bin = bin, cwd = workspace_path }
              )
            )
          end
        end
      end
    end
    table.insert(ret, overseer.wrap_template(tmpl, { name = bin }, { bin = bin }))
    cb(ret)
  end,
}
