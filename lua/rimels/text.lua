--- 纯文本/光标工具函数模块
--- 不依赖任何 rimels 内部模块，仅使用 vim.api

local M = {}

--- 一次性获取光标位置和当前行内容，减少重复 API 调用
--- @return table|nil { cursor = {row, col}, line = string }
function M.get_cursor_context()
  local ok, result = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok or not result then
    return nil
  end
  local row, col = unpack(result)
  local line = ""
  local line_ok, lines = pcall(vim.api.nvim_buf_get_lines, 0, row - 1, row, false)
  if line_ok and lines and #lines > 0 then
    line = lines[1] or ""
  end
  return { cursor = { row, col }, line = line }
end

--- 获取光标后指定长度的字符
--- @param length number 要获取的字符数（默认 1）
--- @param ctx table|nil 可选的 get_cursor_context() 结果
--- @return string
function M.get_chars_after_cursor(length, ctx)
  length = length or 1
  ctx = ctx or M.get_cursor_context()
  if not ctx then
    return ""
  end
  local col = ctx.cursor[2]
  return ctx.line:sub(col + 1, col + length)
end

--- 获取光标前指定偏移量处的字符
--- @param colnums_before number 光标前偏移列数
--- @param length number 要获取的字符数（默认 1）
--- @param ctx table|nil 可选的 get_cursor_context() 结果
--- @return string|nil
function M.get_chars_before_cursor(colnums_before, length, ctx)
  length = length or 1
  if colnums_before < length then
    return nil
  end
  local content_before = M.get_content_before_cursor(colnums_before - length, ctx)
  if not content_before then
    return nil
  end
  return content_before:sub(-length, -1)
end

--- 获取光标前的内容（可指定偏移）
--- @param shift number 偏移量（默认 0）
--- @param ctx table|nil 可选的 get_cursor_context() 结果
--- @return string|nil
function M.get_content_before_cursor(shift, ctx)
  shift = shift or 0
  ctx = ctx or M.get_cursor_context()
  if not ctx then
    return nil
  end
  local col = ctx.cursor[2]
  if col < shift then
    return nil
  end
  return ctx.line:sub(1, col - shift)
end

--- 判断光标是否在行末
--- @return boolean
function M.is_eol()
  return (vim.fn.col "." == vim.fn.col "$")
end

--- 判断是否正在输入英文（光标前为空格 + 英文字符/标点）
--- @param shift number 偏移量
--- @param ctx table|nil 可选的 get_cursor_context() 结果
--- @return boolean|nil
function M.is_typing_english(shift, ctx)
  local content_before = M.get_content_before_cursor(shift, ctx)
  if not content_before then
    return nil
  end
  return content_before:match "%s[%w%p]+$"
end

--- 向输入流馈送按键
--- @param key string 按键字符串
--- @param mode string 模式（默认 "n"）
function M.feedkey(key, mode)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, true, true),
    mode,
    false
  )
end

return M
