local utils = require "rimels.utils"
local M = {}

-- 探针返回值常量：返回 PROBE_BLOCK 表示阻止候选词上屏（探针被触发）
-- 返回 PROBE_ALLOW 表示允许候选词上屏（探针未触发）
local PROBE_ALLOW = false
local PROBE_BLOCK = true

function M.probe_temporarily_disabled()
  if utils.buf_rime_enabled() then
    return PROBE_ALLOW
  else
    return PROBE_BLOCK
  end
end

function M.probe_caps_start()
  if utils.get_content_before_cursor():match "[A-Z][%w]*%s*$" then
    return PROBE_BLOCK
  else
    return PROBE_ALLOW
  end
end

function M.probe_punctuation_after_half_symbol()
  local content_before = utils.get_content_before_cursor(1) or "";
  local word_pre1 = utils.get_chars_before_cursor(1, 1)
  local word_pre2 = utils.get_chars_before_cursor(2, 1)
  if not (word_pre1 and word_pre1:match "[-%p]") then
    return PROBE_ALLOW
  elseif
    not word_pre2 or word_pre2 == ""
    or word_pre2:match('[-%s%p]')
    or (word_pre2:match('%w') and content_before:match('%s%w+$'))
    or (word_pre2:match('%w') and content_before:match('^%w+$'))
  then
    return PROBE_BLOCK
  else
    return PROBE_ALLOW
  end
end

function M.probe_in_mathblock(info)
  info = info or vim.inspect_pos()
  for _, syn in ipairs(info.syntax) do
    if syn.hl_group_link:match "mathblock" then
      return PROBE_BLOCK
    end
  end
  for _, ts in ipairs(info.treesitter) do
    if ts.capture == "markup.math" then
      return PROBE_BLOCK
    end
  end
  return PASS
end

return M
