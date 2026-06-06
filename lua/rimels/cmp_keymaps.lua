local utils = require "rimels.utils"

local M = { keymaps = utils.get_mappings() }

-- 模块级标记：避免兼容层未初始化时重复弹出警告
local _warned_missing_setup = false

---@class Keymap_setup_opts
---@field detectors table
---@field probes table
---@param opts Keymap_setup_opts
function M:setup(opts)
  --- 遍历所有探针，传入预取的 inspect_pos 信息
  --- @param probes_ignored table|string
  --- @param info table|nil 可选的 vim.inspect_pos() 结果，用于避免重复调用
  function self.passed_all_probes(probes_ignored, info)
    if probes_ignored and probes_ignored == "all" then
      return true
    end
    probes_ignored = probes_ignored or {}
    for name, probe in pairs(opts.probes) do
      if not vim.tbl_contains(probes_ignored, name) and probe(info) then
        return false
      end
    end
    return true
  end

  --- 判断光标是否处于英文环境（数学公式、代码块等）
  --- @param info table|nil 可选的 vim.inspect_pos() 结果，避免重复调用
  function self.in_english_environment(info)
    -- 先检查 filetype 再决定是否需要昂贵的 vim.inspect_pos()
    local filetype =
        vim.api.nvim_get_option_value("filetype", { scope = "local" })

    if not filetype or filetype == "" then
      return false
    end

    local detect_english_env = opts.detectors
    local has_treesitter = detect_english_env.with_treesitter[filetype] ~= nil
    local has_syntax = detect_english_env.with_syntax[filetype] ~= nil

    -- 只有配置了检测器才调用 vim.inspect_pos()
    if has_treesitter or has_syntax then
      info = info or vim.inspect_pos()
    end

    if
        has_treesitter
        and detect_english_env.with_treesitter[filetype](info)
    then
      return true
    end

    if
        has_syntax
        and detect_english_env.with_syntax[filetype](info)
    then
      return true
    end

    return false
  end

  return self
end

--- @param info table|nil 可选的 vim.inspect_pos() 结果
function M.autotoggle_backspace(info)
  local rc = { not_toggle = 0, toggle_off = 1, toggle_on = 2 }
  if not utils.buf_rime_enabled() or M.in_english_environment(info) then
    return rc.not_toggle
  end

  -- 统一获取光标上下文，避免重复 API 调用
  local ctx = utils.get_cursor_context()
  if not ctx then
    return rc.not_toggle
  end

  -- 只有在删除空格时才启用输入法切换功能
  local word_before_1 = utils.get_chars_before_cursor(1, 1, ctx)
  if not word_before_1 or word_before_1 ~= " " then
    return rc.not_toggle
  end

  -- 删除连续空格或行首空格时不启动输入法切换功能
  local word_before_2 = utils.get_chars_before_cursor(2, 1, ctx)
  if not word_before_2 or word_before_2 == " " then
    return rc.not_toggle
  end

  -- 删除的空格前是一个空格分隔的 WORD ，或者处在英文输入环境下时，
  -- 切换成英文输入法
  -- 否则切换成中文输入法
  local rime_enabled = utils.global_rime_enabled() -- 缓存，避免重复 pcall
  if utils.is_typing_english(1, ctx) then
    if rime_enabled then
      utils.toggle_rime(utils.get_any_rime_ls_client())
    end
    return rc.toggle_off
  else
    if not rime_enabled then
      utils.toggle_rime(utils.get_any_rime_ls_client())
    end
    return rc.toggle_on
  end
end

--- @param info table|nil 可选的 vim.inspect_pos() 结果
function M.autotoggle_space(info)
  local rc = { not_toggle = 0, toggle_off = 1, toggle_on = 2 }
  if not utils.buf_rime_enabled() or M.in_english_environment(info) then
    return rc.not_toggle
  end

  -- 统一获取光标上下文，避免重复 nvim_win_get_cursor + nvim_get_current_line
  local ctx = utils.get_cursor_context()
  if not ctx then
    return rc.not_toggle
  end

  -- 行首输入空格或输入连续空格时不考虑输入法切换
  local word_before = utils.get_chars_before_cursor(1, 1, ctx)
  if not word_before or word_before == " " then
    return rc.not_toggle
  end

  -- 在英文输入状态下，如果光标后为英文符号，则不切换成中文输入状态
  -- 例如：(abc|)
  local char_after = utils.get_chars_after_cursor(1, ctx)
  local rime_enabled = utils.global_rime_enabled() -- 缓存，避免重复 pcall
  if
    not rime_enabled
    and char_after
    and char_after ~= ""
    and char_after:match "[!-~]"
  then
    return rc.not_toggle
  end

  -- 最后一个字符为英文字符，数字或标点符号时，切换为中文输入法
  -- 否则切换为英文输入法
  if word_before:match "[%w%p]" then
    if not rime_enabled then
      utils.toggle_rime(utils.get_any_rime_ls_client())
    end
    return rc.toggle_on
  else
    if rime_enabled then
      utils.toggle_rime(utils.get_any_rime_ls_client())
    end
    return rc.toggle_off
  end
end

--- 判断输入法候选词是否应该上屏
--- 统一获取一次 vim.inspect_pos() 结果，传给所有探针避免重复调用
--- @param entry table 补全条目
--- @param probes_ignored table|string 忽略的探针列表
--- @param info table|nil 可选的 vim.inspect_pos() 结果，由调用方预取
--- @return boolean
function M.input_method_take_effect(entry, probes_ignored, info)
  if not entry then
    return false
  end

  if not M.passed_all_probes then
    if not _warned_missing_setup then
      _warned_missing_setup = true
      vim.notify(
        "rimels: 请先调用 :setup() 完成 probes 初始化",
        vim.log.levels.WARN
      )
    end
    return false
  end
  -- 使用预取结果或获取（当调用方未提供时）
  info = info or vim.inspect_pos()
  if utils.is_rime_entry(entry) and M.passed_all_probes(probes_ignored, info) then
    return true
  else
    return false
  end
end

-- number --------------------------------------------------------------- {{{3
for numkey = 1, 9 do
  local numkey_str = tostring(numkey)
  M.keymaps[numkey_str] = utils.generate_mapping(function(_)
    if not utils.buf_rime_enabled() then
      return utils.fallback(numkey_str)
    end
    if not utils.is_cmp_visible() then
      if utils.global_rime_enabled() then
        utils.toggle_rime(utils.buf_get_rime_ls_client(), true)
      end
      return utils.fallback(numkey_str)
    end
    utils.feedkey(numkey_str, "n")
    return utils.cmp_without_processing()
  end)
end

-- <Space> -------------------------------------------------------------- {{{3
M.keymaps["<Space>"] = utils.generate_mapping(function(_)
  -- 仅在进入补全模式时才清理上次条目，不在每次空格做无用功
  if not utils.is_cmp_visible() then
    M.autotoggle_space() -- info 不传，内部按需获取
    return utils.fallback("<Space>")
  end

  -- 补全可见：清理旧状态并预取 inspect_pos 供后续共享
  if pcall(vim.api.nvim_buf_get_var, 0, "rimels_last_entry") then
    vim.api.nvim_buf_del_var(0, "rimels_last_entry")
  end

  -- 补全可见时预取 inspect_pos，后续 autotoggle_space 和
  -- input_method_take_effect 可共享，避免重复昂贵调用
  local info = vim.inspect_pos()
  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()

  if select_entry then
    if utils.is_rime_entry(select_entry) then
      utils.cmp_confirm(false)
    else
      M.autotoggle_space(info)
      return utils.fallback("<Space>")
    end
  end

  if M.input_method_take_effect(first_entry, nil, info) then
    local new_result = utils.adjust_for_rimels(first_entry)
    if new_result then
      first_entry.label = new_result
      if first_entry and first_entry.textEdit then
        first_entry.textEdit.newText = new_result
      end
    end
    utils.set_last_entry(first_entry)
    return utils.cmp_confirm(true)
  end

  M.autotoggle_space(info)
  return utils.fallback("<Space>")
end)

-- <CR> ----------------------------------------------------------------- {{{3
M.keymaps["<CR>"] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    return utils.fallback("<CR>")
  end

  -- 预取 inspect_pos，input_method_take_effect 和 in_english_environment 共享
  local info = vim.inspect_pos()
  local select_entry = utils.get_selected_entry()
  local first_entry = utils.get_first_entry()
  local entry = select_entry or first_entry

  if not entry then
    return utils.fallback("<CR>")
  end

  if M.input_method_take_effect(entry, "all", info) then
    if M.in_english_environment(info) then
      utils.toggle_rime(utils.get_any_rime_ls_client())
    end
    utils.cmp_close()
    utils.feedkey(" ", "n")
  elseif
      select_entry
      and utils.get_cmp_source_name(select_entry) ~= "nvim_lsp_signature_help"
  then
    return utils.cmp_confirm(true)
  else
    return utils.cmp_close()
  end

  return utils.cmp_without_processing()
end)

-- rime 选词定字：从候选词中取第一个字或最后一个字 ----------------------- {{{3
--- @param key string 原始按键（用于 fallback）
--- @param position 1|"last" 取第一个字(1)或最后一个字("last")
local function rime_take_char(key, position)
  return utils.generate_mapping(function(_)
    if not utils.is_cmp_visible() then
      return utils.fallback(key)
    end

    local select_entry = utils.get_selected_entry()
    local first_entry = utils.get_first_entry()
    local entry = select_entry or first_entry

    if not entry then
      return utils.fallback(key)
    end

    if M.input_method_take_effect(entry) then
      local text = utils.get_cmp_result(entry)
      text = vim.fn.split(text, "\\zs")
      text = position == "last" and text[#text] or text[1]
      utils.cmp_close()
      vim.schedule(function()
        local input =
            utils.get_input_code(entry):gsub("[^\1-\127]*([\1-\127]+)$", "%1")
        vim.api.nvim_put({ text }, "c", true, true)
        utils.feedkey("<left>", "n")
        for _ = 1, input:len() do
          utils.feedkey("<bs>", "n")
        end
        utils.feedkey("<right>", "n")
      end)
    else
      return utils.fallback(key)
    end

    return utils.cmp_without_processing()
  end)
end

M.keymaps["["] = rime_take_char("[", 1)
M.keymaps["]"] = rime_take_char("]", "last")

-- <bs> ----------------------------------------------------------------- {{{3
M.keymaps["<BS>"] = utils.generate_mapping(function(_)
  if not utils.is_cmp_visible() then
    local re = M.autotoggle_backspace()
    if re == 1 then
      utils.cmp_close()
      utils.feedkey("<left>", "n")
    else
      return utils.fallback("<BS>")
    end
  else
    return utils.fallback("<BS>")
  end

  return utils.cmp_without_processing()
end)

function M:launch(disable)
  local mappings = utils.filter_cmp_keymaps(self.keymaps, disable or {})
  if not next(mappings) then
    return
  end

  -- 安全检查：确保 blink.cmp 可用再注册 autocmd
  local ok, blink_config = pcall(require, "blink.cmp.config")
  if not ok then
    vim.notify(
      "rimels: 未检测到 blink.cmp，请确保已安装 blink.cmp 插件",
      vim.log.levels.WARN
    )
    return
  end

  vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function()
      if not blink_config.enabled() then
        return
      end
      utils.blink_apply_keymap(mappings)
    end,
  })

  if
      vim.api.nvim_get_mode().mode == "i"
      and blink_config.enabled()
  then
    utils.blink_apply_keymap(mappings)
  end

  return mappings
end

return M
