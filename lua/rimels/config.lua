-- Module for handling rimels plugin option configuration and merging
local default = require "rimels.default_opts"
local probes = require "rimels.probes"
local detectors = require "rimels.english_environment_detectors"

local M = {}

--- 验证用户配置的字段类型，发现无效值时发出警告
--- @param user table 用户提供的配置
local function validate_opts(user)
  if not user then
    return
  end

  -- 检查常见配置字段的类型
  local checks = {
    { "cmd", { "string", "table" } },
    { "rime_user_dir", { "string" } },
    { "shared_data_dir", { "string" } },
    { "max_candidates", { "number" } },
    { "schema_trigger_character", { "string" } },
  }
  for _, check in ipairs(checks) do
    local field, expected = check[1], check[2]
    local val = user[field]
    if val ~= nil then
      local ok = false
      for _, t in ipairs(expected) do
        if type(val) == t then
          ok = true
          break
        end
      end
      if not ok then
        vim.notify(
          string.format(
            "rimels: 配置字段 %s 类型应为 %s，当前为 %s",
            field,
            table.concat(expected, "|"),
            type(val)
          ),
          vim.log.levels.WARN
        )
      end
    end
  end

  -- 验证 keys 子表
  if user.keys then
    local key_names = { "start", "stop", "esc", "undo" }
    for _, k in ipairs(key_names) do
      local v = user.keys[k]
      if v ~= nil and type(v) ~= "string" then
        vim.notify(
          string.format("rimels: keys.%s 应为字符串，当前为 %s", k, type(v)),
          vim.log.levels.WARN
        )
      end
    end
  end

  -- 验证 cmp_keymaps.disable 子表
  if user.cmp_keymaps and user.cmp_keymaps.disable then
    local disable_names = {
      "space", "numbers", "enter", "brackets",
      "backspace", "punctuation_upload_directly",
    }
    for _, k in ipairs(disable_names) do
      local v = user.cmp_keymaps.disable[k]
      if v ~= nil and type(v) ~= "boolean" then
        vim.notify(
          string.format(
            "rimels: cmp_keymaps.disable.%s 应为布尔值，当前为 %s",
            k,
            type(v)
          ),
          vim.log.levels.WARN
        )
      end
    end
  end
end

--- Update and merge user options with default configuration
--- @param user table|nil User-provided options to merge with defaults
--- @return table Merged options configuration
function M.update_option(user)
  -- 验证传入配置的类型
  validate_opts(user)

  -- Return defaults if no user options provided or table is empty
  if not (user and next(user)) then
    return default
  end

  -- Normalize cmd option: convert string to table format for consistency
  if user.cmd and type(user.cmd) == "string" then
    user.cmd = { user.cmd }
  end

  -- Deep merge user options with defaults, user options take precedence
  local opts = vim.tbl_deep_extend("force", default, user)

  -- Configure probes: include all available probes except those explicitly ignored
  for name, probe in pairs(probes) do
    -- Only add probe if it's not in the ignore list
    if not vim.tbl_contains(opts.probes.ignore, name) then
      opts.probes.using[name] = probe
    end
  end

  -- Merge in any additional custom probes specified by user
  opts.probes.using = vim.tbl_extend("force", opts.probes.using, opts.probes.add)

  -- Configure detectors by merging default detectors with user-provided ones
  opts.detectors = {
    with_treesitter = vim.tbl_extend(
      "force",
      detectors.with_treesitter,
      opts.detectors.with_treesitter or {}
    ),
    with_syntax = vim.tbl_extend(
      "force",
      detectors.with_syntax,
      opts.detectors.with_syntax or {}
    ),
  }

  return opts
end

return M
