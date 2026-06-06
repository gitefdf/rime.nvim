--- LSP 客户端管理模块
--- 负责 rime_ls 的生命周期、配置、状态切换和 autocmd 创建

local cmp = require "rimels.cmp"
local text = require "rimels.text"

local M = {}

-- 版本检测常量
M.has_nvim_0_10_2 = vim.fn.has "nvim-0.10.2" == 1
M.has_nvim_0_11 = vim.fn.has "nvim-0.11.0" == 1

-- 全局/缓冲区状态变量名
local GLOBAL_RIME_VAR = "nvim_rime#global_rime_enabled"
local BUF_RIME_VAR = "buf_rime_enabled"

-- 模块级常量
local RIME_LS_RETRY_MAX = 10 -- start_rime_ls 最大重试次数

-- Cached blink.cmp for generate_capabilities
local blink_cmp

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

--- 将 rime_ls 客户端附加到指定缓冲区
--- @param bufnr number|nil 目标缓冲区编号，默认当前缓冲区
function M.buf_attach_rime_ls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_get_rime_ls_client(bufnr) then
    return
  end

  local client = M.get_any_rime_ls_client()
  if client then
    vim.lsp.buf_attach_client(bufnr, client.id)
    return
  end

  M.launch_rime_ls()
end

--- 获取指定缓冲区上附加的 rime_ls 客户端
--- @param bufnr number|nil 目标缓冲区编号
--- @return table|nil
function M.buf_get_rime_ls_client(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_rimels_clients =
      vim.lsp.get_clients { bufnr = bufnr, name = "rime_ls" }
  if #buffer_rimels_clients > 0 then
    return buffer_rimels_clients[1]
  end
  return nil
end

-- rime_ls 客户端缓存（模块级，避免每次按键扫描全部 LSP 客户端）
local _cached_rime_client = nil

--- 按名称查找任意 rime_ls 客户端（不限 buffer 附着）
--- 结果在模块级缓存，客户端生命周期内不会改变
--- 当无法通过 buffer 获取客户端时使用（如 terminal/special buffer）
--- @return table|nil 返回第一个 rime_ls 客户端或 nil
function M.get_any_rime_ls_client()
  if _cached_rime_client ~= nil then
    return _cached_rime_client
  end
  local clients = vim.lsp.get_clients { name = "rime_ls" }
  if #clients > 0 then
    _cached_rime_client = clients[1]
  end
  return _cached_rime_client
end

--- 检查指定缓冲区是否已启用 Rime
--- @param bufnr number|nil
--- @return boolean
function M.buf_rime_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local exist, status =
      pcall(vim.api.nvim_buf_get_var, bufnr, BUF_RIME_VAR)
  return (exist and status)
end

--- 切换缓冲区的 Rime 状态
--- @param bufnr number|nil
--- @param buf_only boolean 仅切换缓冲区状态，不触发 LSP 命令
function M.buf_toggle_rime(bufnr, buf_only)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if M.buf_rime_enabled(bufnr) ~= M.global_rime_enabled() or buf_only then
    vim.api.nvim_buf_set_var(
      bufnr,
      BUF_RIME_VAR,
      not M.buf_rime_enabled(bufnr)
    )
    return
  end

  local client = M.buf_get_rime_ls_client(bufnr)
  if not client then
    M.buf_attach_rime_ls(bufnr)
    client = M.buf_get_rime_ls_client(bufnr)
  end
  if not client then
    vim.notify("Failed to get rime_ls client", vim.log.levels.ERROR)
    return
  end

  M.toggle_rime(client)
  M.buf_toggle_rime(bufnr, true)
end

--- 创建根据缓冲区状态自动切换 Rime 的 autocmd
--- @param client table rime_ls 客户端
function M.create_autocmd_toggle_rime_according_buffer_status(client)
  local rime_group =
      vim.api.nvim_create_augroup("RimeAutoToggle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufRead" }, {
    pattern = "*",
    group = rime_group,
    callback = function(ev)
      local bufnr = ev.buf
      if not M.buf_get_rime_ls_client(bufnr) then
        return
      end
      local buf_rime_enabled = M.buf_rime_enabled(bufnr)
      local global_rime_enabled = M.global_rime_enabled()
      if buf_rime_enabled ~= global_rime_enabled then
        M.toggle_rime(client)
      end
    end,
    desc = "Start or stop rime_ls according current buffer",
  })
end

--- 创建 RimeSync 用户命令
function M.create_command_rime_sync()
  vim.api.nvim_create_user_command("RimeSync", function()
    local client = M.buf_get_rime_ls_client()
    if client and client.exec_cmd then -- Neovim ≥ 0.10
      client:exec_cmd {
        title = "Sync Rime user data",
        command = "rime-ls.sync-user-data",
      }
    elseif client then -- 旧版兼容
      ---@diagnostic disable-next-line: deprecated
      vim.lsp.buf.execute_command {
        command = "rime-ls.sync-user-data",
      }
    end
  end, { nargs = 0 })
end

--- 创建 ToggleRime 用户命令
--- @param client table rime_ls 客户端
function M.create_command_toggle_rime(client)
  vim.api.nvim_create_user_command("ToggleRime", function(opt)
    local bufnr = vim.api.nvim_get_current_buf()
    local args = opt.args
    if
        (not args or args == "")
        or (args == "on" and not M.global_rime_enabled())
        or (args == "off" and M.global_rime_enabled())
    then
      M.toggle_rime(client)
    elseif args == "start" and not M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    M.buf_toggle_rime(bufnr, true)
  end, { nargs = "?", desc = "Toggle Rime" })
end

--- 创建启动输入法的按键映射（esc 退出插入模式）
--- @param key string 按键
function M.create_inoremap_esc(key)
  vim.keymap.set(
    "i",
    key,
    "<cmd>stopinsert<cr>",
    { desc = "Stop insert", noremap = true, buffer = true }
  )
end

--- 创建启动输入法的按键映射
--- @param client table rime_ls 客户端
--- @param key string 按键
function M.create_inoremap_start_rime(client, key)
  vim.keymap.set("i", key, function()
    if not M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    if not M.buf_rime_enabled() then
      M.buf_toggle_rime(0, true)
    end
  end, {
    desc = "Start Chinese Input Method",
    noremap = true,
    buffer = true,
  })
end

--- 创建停止输入法的按键映射
--- @param client table rime_ls 客户端
--- @param key string 按键
function M.create_inoremap_stop_rime(client, key)
  vim.keymap.set("i", key, function()
    if cmp.is_cmp_visible() then
      cmp.cmp_close()
    end
    if M.global_rime_enabled() then
      M.toggle_rime(client)
    end
    if M.buf_rime_enabled() then
      M.buf_toggle_rime(0, true)
    end
  end, {
    desc = "Stop Chinese Input Method",
    noremap = true,
    buffer = true,
  })
end

--- 创建撤销上屏的按键映射
--- @param key string 按键
function M.create_inoremap_undo(key)
  local fallback_fn = function()
    local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(keys, "n", false)
  end

  vim.keymap.set("i", key, function()
    -- Use vim.b for buffer-local variables for better performance and readability
    if vim.b.rimels_last_entry == nil then
      return fallback_fn()
    end
    if cmp.is_cmp_visible() then
      return fallback_fn()
    end

    local entry = vim.b.rimels_last_entry
    -- Guard against malformed entry
    if
        not entry.filterText
        or not entry.textEdit
        or not entry.textEdit.newText
        or vim.fn.line "." ~= entry.textEdit.range["end"].line + 1
    then
      return fallback_fn()
    end

    local text_cmp = entry.textEdit.newText
    local text_input = entry.filterText
    local content_before = text.get_content_before_cursor(0) or ""

    -- Ensure the text before the cursor ends with the completed text
    if not content_before:match(vim.pesc(text_cmp) .. "$") then
      return fallback_fn()
    end

    -- Undo the completion by deleting characters and re-inserting original input
    local char_num = vim.fn.strchars(text_cmp)
    text.feedkey(string.rep("<BS>", char_num), "n")

    text_input = text_input:gsub(".*_", "")
    vim.schedule(function()
      vim.api.nvim_put({ text_input }, "c", false, true)
    end)
  end, { desc = "rimels: undo last completion", noremap = true, buffer = true })
end

--- rime_ls 未启动时的错误提示
function M.error_rime_ls_not_start_yet()
  local status_ok, notify = pcall(require, "notify")
  if status_ok then
    notify("Start rime-ls with command ToggleRimeLS", "error", {
      title = "rime-ls framework not start yet",
    })
  else
    vim.fn.echoerr "Start rime-ls with command ToggleRimeLS"
  end
end

--- 生成 LSP capabilities 配置
--- @return table
function M.generate_capabilities()
  local blink = get_blink_cmp()
  if not blink then
    return {}
  end

  -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities = blink.get_lsp_capabilities(capabilities)

  -- Fix: Offset-Encoding issue since Neovim v0.10.2 #38
  if M.has_nvim_0_10_2 and not M.has_nvim_0_11 then
    capabilities.general = capabilities.general or {}
    capabilities.general.positionEncodings = { "utf-8" }
  end

  return capabilities
end

--- 检查 Rime 输入法是否全局启用
--- @return boolean
function M.global_rime_enabled()
  local ok, val = pcall(vim.api.nvim_get_var, GLOBAL_RIME_VAR)
  return ok and val == true
end

--- 启动 rime_ls（Neovim 版本兼容）
function M.launch_rime_ls()
  if M.has_nvim_0_11 then
    vim.lsp.enable "rime_ls"
  else
    require("lspconfig").rime_ls.launch()
  end
end

--- 配置并启动 rime_ls 语言服务器
--- @param opts table 配置选项
function M.rime_ls_setup(opts)
  local rime_on_attach = function(client, _)
    M.create_command_toggle_rime(client)
    M.create_command_rime_sync()
    M.create_autocmd_toggle_rime_according_buffer_status(client)
    M.create_inoremap_start_rime(client, opts.keys.start)
    M.create_inoremap_stop_rime(client, opts.keys.stop)
    M.create_inoremap_esc(opts.keys.esc)
    M.create_inoremap_undo(opts.keys.undo)
  end

  local blink = get_blink_cmp()

  local lsp_opts = {
    init_options = {
      enabled = M.global_rime_enabled(),
      shared_data_dir = opts.shared_data_dir,
      user_data_dir = opts.user_data_dir or opts.rime_user_dir,
      log_dir = opts.rime_user_dir .. "/log",
      max_candidates = opts.max_candidates,
      long_filter_text = blink and true or opts.long_filter_text,
      trigger_characters = opts.trigger_characters,
      schema_trigger_character = opts.schema_trigger_character,
      always_incomplete = opts.always_incomplete,
      paging_characters = opts.paging_characters,
    },
    on_attach = rime_on_attach,
    capabilities = M.generate_capabilities(),
  }

  if not M.has_nvim_0_11 then
    local lspconfigs = require "lspconfig.configs"
    if not lspconfigs.rime_ls then
      lspconfigs.rime_ls = {
        default_config = {
          name = "rime_ls",
          cmd = opts.cmd,
          root_dir = function() end,
          filetypes = opts.filetypes,
          single_file_support = opts.single_file_support,
        },
        settings = opts.settings,
        docs = {
          description = opts.docs.description,
        },
      }
    end

    require("lspconfig").rime_ls.setup(lsp_opts)
  else
    lsp_opts.name = "rime_ls"
    lsp_opts.cmd = opts.cmd
    vim.lsp.config("rime_ls", lsp_opts)
  end
end

--- 在指定缓冲区启动 Rime 语言服务器
---
--- 包含递归重试机制处理首次挂载问题
---
--- @param iters? number 当前重试次数（默认 0）
function M.start_rime_ls(iters)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = M.buf_get_rime_ls_client(bufnr)

  if not client then
    -- Attach the Rime LS client to the buffer if not already attached
    M.buf_attach_rime_ls(bufnr)
    -- Retry mechanism to ensure input method takes effect on first start
    iters = iters or 0
    if iters <= RIME_LS_RETRY_MAX then
      vim.schedule(function()
        M.start_rime_ls(iters + 1)
      end)
    end
    return
  end

  -- Enable Rime globally if not already enabled
  if not M.global_rime_enabled() then
    M.toggle_rime(client)
  end

  -- Enable Rime for the buffer if not already enabled
  if not M.buf_rime_enabled() then
    M.buf_toggle_rime(bufnr, true)
  end
end

--- 通过 LSP 命令切换 Rime 输入法状态
---
--- @param client table|nil rime_ls LSP 客户端，为 nil 时自动获取
--- @param synchronously boolean|nil 为 true 时立即执行，否则调度到下一事件循环
function M.toggle_rime(client, synchronously)
  -- Retrieve client if not provided, with fallback to buffer-specific client
  client = client or M.buf_get_rime_ls_client()

  -- Validate client exists and is the correct rime_ls instance
  if not client or client.name ~= "rime_ls" then
    vim.notify("No valid rime_ls client available", vim.log.levels.WARN)
    return
  end

  -- Define the toggle operation with improved error handling
  local function execute_toggle_request()
    client:request(
      "workspace/executeCommand",
      { command = "rime-ls.toggle-rime" },
      function(err, result, ctx, _)
        -- Handle request errors
        if err then
          vim.notify(
            "Failed to toggle Rime: " .. tostring(err),
            vim.log.levels.ERROR
          )
          return
        end

        -- Update global status only for the correct client and valid result
        if ctx and ctx.client_id == client.id and result ~= nil then
          vim.api.nvim_set_var(GLOBAL_RIME_VAR, true)
        else
          vim.api.nvim_set_var(GLOBAL_RIME_VAR, false)
        end
      end
    )
  end

  -- Execute the toggle request either synchronously or asynchronously
  if synchronously then
    execute_toggle_request()
  else
    vim.schedule(execute_toggle_request)
  end
end

return M
