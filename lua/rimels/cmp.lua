--- 补全框架交互模块
--- 封装 blink.cmp 操作和候选词处理逻辑

local text = require "rimels.text"

local M = {}

-- Cached blink.cmp modules for performance
local blink_cmp
local blink_cmp_completion_list

---@return table|nil
local function get_blink_cmp()
  if blink_cmp == nil then
    local ok, mod = pcall(require, "blink.cmp")
    if ok then
      blink_cmp = mod
    end
  end
  return blink_cmp
end

---@return table|nil
local function get_completion_list()
  if blink_cmp_completion_list == nil then
    local ok, mod = pcall(require, "blink.cmp.completion.list")
    if ok then
      blink_cmp_completion_list = mod
    end
  end
  return blink_cmp_completion_list
end

--- 临时解决 rime-ls 中 * 和 [ 等符号被吞入前缀的问题，会随上游更新调整
--- 跟踪: https://github.com/wlh320/rime-ls/issues/10
--- 当 rime-ls 修复后，可移除此函数
--- @param entry table 补全条目
--- @return string|nil 调整后的结果
function M.adjust_for_rimels(entry)
  local input_code = M.get_input_code(entry)
  local cmp_result = M.get_cmp_result(entry)
  local special_symbol_pattern = "[%[%]{}]"
  local other_symbol_pattern = "[^%[%]{}]"
  if input_code:match(special_symbol_pattern .. "[A-Za-z]") then
    local pattern =
        string.format("^.*(%s)%s+$", special_symbol_pattern, other_symbol_pattern)
    local prefix = input_code:gsub(pattern, "%1")
    if
        prefix:sub(1, 1) == prefix:sub(2, 2)
        and prefix:sub(1, 1):match(special_symbol_pattern)
    then
      prefix = prefix:sub(2)
    end
    return prefix .. cmp_result
  end
end

--- Apply blink.cmp keymaps to the current buffer
---
--- This function sets up insert mode keymaps for blink.cmp completion commands.
--- It avoids duplicate application by checking a buffer-local flag.
---
--- @param keys_to_commands table A table mapping keys to arrays of commands
function M.blink_apply_keymap(keys_to_commands)
  -- 使用 buffer 局部标记避免每次 InsertEnter 都扫描映射
  if vim.b.rimels_keymaps_applied then
    return
  end
  vim.b.rimels_keymaps_applied = true

  -- 设置 keymaps
  local DESC_PREFIX = "blink.cmp: rimels"
  local blink = get_blink_cmp()

  -- Cache required modules to reduce repeated require() calls
  local blink_config = require "blink.cmp.config"

  -- Apply keymaps for each key-command combination
  for key, commands in pairs(keys_to_commands) do
    -- Skip keys with no commands to avoid unnecessary mappings
    if #commands > 0 then
      vim.keymap.set("i", key, function()
        if not blink_config.enabled() then
          M.fallback(key)
          return
        end

        for _, command in ipairs(commands) do
          if command == "fallback" then
            M.fallback(key)
            return
          elseif type(command) == "function" then
            local ret = command(blink)
            if ret then
              if type(ret) == "string" then
                text.feedkey(ret, "n")
              end
              return
            end
          elseif blink[command] and blink[command]() then
            return
          end
        end
      end, {
        desc = DESC_PREFIX,
        silent = true,
        noremap = true,
        buffer = 0,
      })
    end
  end
end

--- 关闭补全菜单
function M.cmp_close()
  local blink = get_blink_cmp()
  if blink and blink.is_visible() then
    blink.hide()
  end
end

--- 确认补全
--- @param select boolean 是否选中当前高亮项
function M.cmp_confirm(select)
  local blink = get_blink_cmp()

  select = select ~= false
  if select then
    return blink.select_and_accept()
  else
    return blink.accept()
  end
end

--- 处理标点符号上屏时的特殊情况
--- @param entries table 补全条目列表
function M.cmp_confirm_punction(entries)
  local rime_id = M.get_rime_entry_ids(entries, { only = true })
  if not rime_id then
    return
  end

  -- check character before the punctuation
  local word_before = text.get_chars_before_cursor(2)
  if not word_before or word_before == "" then
    M.cmp_close()
  elseif not word_before:match "[%s%w%p]" then
    M.set_last_entry(entries[rime_id])
    M.cmp_select_nth(rime_id)
  end
end

--- 占位返回值，表示需要中断命令链的处理
--- @return true
function M.cmp_without_processing()
  return true
end

--- 选择第 n 个条目并上屏
--- @param n number 条目索引
--- @param entries table|nil 补全条目列表
function M.cmp_select_nth(n, entries)
  local blink = get_blink_cmp()

  entries = entries or blink.get_items() or {}
  vim.b.rimels_last_entry = entries[n]
  blink.accept { index = n }
end

--- blink.cmp fallback: 将按键传递给下层映射
--- @param lhs string 按键字符串
--- @return true
function M.fallback(lhs)
  if type(lhs) ~= "string" or lhs == "" then
    error("rimels.utils.fallback: lhs must be a non-empty string", 2)
  end

  local function feed(key, mode)
    local translated = key:find("\128") and key or vim.keycode(key)
    vim.api.nvim_feedkeys(translated, mode or "n", false)
  end

  -- blink.cmp V1 returns a key string; V2 returns a `{ key, mode }[]` array.
  local keys = require("blink.cmp.keymap.fallback").wrap("i", lhs)()
  if type(keys) == "string" then
    feed(keys)
  elseif type(keys) == "table" then
    for _, k in ipairs(keys) do feed(k.key, k.mode) end
  end

  return true
end

--- 根据 disable 配置过滤需要禁用的 keymaps
--- @param keymaps table 原始 keymaps
--- @param disable table 禁用配置
--- @return table 过滤后的 keymaps
function M.filter_cmp_keymaps(keymaps, disable)
  if not keymaps then
    return {}
  end
  if not disable then
    return keymaps
  end

  if disable.space then
    keymaps["<Space>"] = nil
  end
  if disable.enter then
    keymaps["<CR>"] = nil
  end
  if disable.backspace then
    keymaps["<BS>"] = nil
  end
  if disable.brackets then
    keymaps["["] = nil
    keymaps["]"] = nil
  end

  return keymaps
end

--- 生成带 fallback 保护的映射命令序列
--- 如果 fun 忘记返回 utils.fallback(lhs)，末尾的 "fallback" 仍然会消费按键
--- @param fun function 映射回调函数
--- @return table 命令序列
function M.generate_mapping(fun)
  return {
    fun,
    "fallback",
  }
end

--- 获取补全条目的上屏文本
--- @param entry table
--- @return string|nil
function M.get_cmp_result(entry)
  return vim.tbl_get(entry, "textEdit", "newText")
end

--- 获取补全条目的来源名称
--- @param entry table
--- @return string|nil
function M.get_cmp_source_name(entry)
  if not entry then
    return
  end
  return entry.source_id
end

--- 获取第一个补全条目
--- @return table|nil
function M.get_first_entry()
  local blink = get_blink_cmp()
  if not blink then
    return
  end
  local entries = blink.get_items()
  if entries and #entries > 0 then
    return entries[1]
  end
end

--- 获取输入码（filterText）
--- @param entry table
--- @return string
function M.get_input_code(entry)
  return entry.filterText
end

--- 获取默认 keymaps
--- @return table
function M.get_mappings()
  local blink = get_blink_cmp()
  if not blink then
    return {}
  end
  return require("blink.cmp.keymap").get_mappings(
    require("blink.cmp.config").keymap,
    "default"
  )
end

--- 获取补全条目中 rime 候选词的索引
--- @param entries table 补全条目列表
--- @param opts table|nil 选项:
---   first  - 仅返回第一个 rime 条目的索引 (number|nil)
---   only   - 仅当只有一个 rime 条目时返回其索引，否则返回 nil
---   number - 返回第 N 个 rime 条目的索引 (number|nil)
--- 未指定选项时返回所有 rime 条目索引的列表 (table)
--- @return number|nil|table
function M.get_rime_entry_ids(entries, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    first = false,
    only = false,
    number = nil,
  })
  if opts.number and type(opts.number) == "string" then
    opts.number = tonumber(opts.number)
  end

  local ids = {}
  for id, entry in ipairs(entries) do
    if M.is_rime_entry(entry) then
      table.insert(ids, id)
      -- 仅需要一个 rime 条目时，发现多个则返回 nil
      if opts.only and #ids > 1 then
        return nil
      end
      -- 查找第一个 rime 条目
      if opts.first then
        return ids[1]
      end
      -- 查找第 N 个 rime 条目
      if opts.number and #ids >= opts.number then
        return ids[opts.number]
      end
    end
  end

  -- 未指定选项或 only/first 找到 1 个时返回 ids[1]
  if opts.only or opts.first then
    return ids[1]
  end
  return ids
end

--- 获取当前高亮的补全条目
--- @return table|nil
function M.get_selected_entry()
  local blink = get_blink_cmp()
  if not blink then
    return
  end
  return get_completion_list().get_selected_item()
end

--- 判断补全菜单是否可见
--- @return boolean
function M.is_cmp_visible()
  local blink = get_blink_cmp()
  return blink and blink.is_visible()
end

--- 判断是否为 rime_ls 返回的候选词
--- @param entry table
--- @return boolean
function M.is_rime_entry(entry)
  if not entry then
    return false
  end

  local input = M.get_input_code(entry)
  local result = M.get_cmp_result(entry)
  local client = vim.lsp.get_client_by_id(entry.client_id)

  return entry.source_id == "lsp"
      and client
      and client.name == "rime_ls"
      and input ~= result
      and input:sub(-result:len(), -1) ~= result
end

--- 记录最近一次选中的条目
--- @param entry table
function M.set_last_entry(entry)
  vim.b.rimels_last_entry = entry
end

return M
