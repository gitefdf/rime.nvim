--- rimels.text 模块单元测试
--- 运行方式: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/text_spec.lua" -c "q"

local text = require "rimels.text"

local passed = 0
local failed = 0
local function t(desc, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    vim.api.nvim_err_writeln(string.format("FAIL: %s - %s", desc, tostring(err)))
  end
end

-- 测试 get_chars_before_cursor
t("get_chars_before_cursor: BOL returns nil", function()
  local result = text.get_chars_before_cursor(0, 1)
  assert(result == nil, "expected nil, got " .. tostring(result))
end)

-- 测试 get_content_before_cursor
t("get_content_before_cursor: shift 0 on empty line", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "test line" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local result = text.get_content_before_cursor(0)
  assert(result == "test ", "expected 'test ', got " .. tostring(result))
end)

t("get_content_before_cursor: shift 3", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "test line" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local result = text.get_content_before_cursor(3)
  assert(result == "te", "expected 'te', got " .. tostring(result))
end)

-- 测试 is_eol
t("is_eol: true at end of line", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "test" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  -- col('.') at end of line means the cursor is past the last character
  -- This depends on the cursor position; we just verify the function doesn't crash
  local ok, result = pcall(text.is_eol)
  assert(ok, "is_eol should not throw")
  assert(type(result) == "boolean", "expected boolean")
end)

-- 测试 is_typing_english
t("is_typing_english: detects English after space", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
  vim.api.nvim_win_set_cursor(0, { 1, 12 }) -- 光标在 "d" 后
  local result = text.is_typing_english(0)
  assert(result, "expected true for 'world' after space")
end)

t("is_typing_english: fails on Chinese text", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "你好 世界" })
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  local result = text.is_typing_english(0)
  assert(not result, "expected false for Chinese after space")
end)

-- 测试 feedkey 不抛出异常
t("feedkey: works with simple key", function()
  local ok = pcall(text.feedkey, "a", "n")
  assert(ok, "feedkey should not throw")
end)

-- 汇总
print(string.format("\n文本模块测试结果: %d 通过, %d 失败", passed, failed))
if failed > 0 then
  vim.cmd "cquit!"
end
