--- rimels.cmp 模块纯函数单元测试
--- 只测试不依赖 blink.cmp 运行时的函数
--- 运行方式: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/cmp_spec.lua" -c "q!"

local cmp = require "rimels.cmp"

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

-- 测试 filter_cmp_keymaps
t("filter_cmp_keymaps: nil keymaps returns empty", function()
  local result = cmp.filter_cmp_keymaps(nil, {})
  assert(type(result) == "table", "expected table")
  assert(#result == 0 or next(result) == nil, "expected empty table")
end)

t("filter_cmp_keymaps: nil disable returns original", function()
  local km = { a = 1, b = 2 }
  local result = cmp.filter_cmp_keymaps(km, nil)
  assert(result == km, "expected original table back")
end)

t("filter_cmp_keymaps: disables space", function()
  local km = { ["<Space>"] = {}, ["<CR>"] = {} }
  local result = cmp.filter_cmp_keymaps(km, { space = true })
  assert(result["<Space>"] == nil, "Space should be nil")
  assert(result["<CR>"] ~= nil, "CR should remain")
end)

t("filter_cmp_keymaps: disables enter", function()
  local km = { ["<CR>"] = {}, a = {} }
  local result = cmp.filter_cmp_keymaps(km, { enter = true })
  assert(result["<CR>"] == nil, "CR should be nil")
end)

t("filter_cmp_keymaps: disables brackets", function()
  local km = { ["["] = {}, ["]"] = {}, a = {} }
  local result = cmp.filter_cmp_keymaps(km, { brackets = true })
  assert(result["["] == nil, "[ should be nil")
  assert(result["]"] == nil, "] should be nil")
  assert(result.a ~= nil, "a should remain")
end)

t("filter_cmp_keymaps: disables backspace", function()
  local km = { ["<BS>"] = {}, a = {} }
  local result = cmp.filter_cmp_keymaps(km, { backspace = true })
  assert(result["<BS>"] == nil, "BS should be nil")
end)

-- 测试 generate_mapping
t("generate_mapping: wraps function with fallback", function()
  local fn = function() return true end
  local result = cmp.generate_mapping(fn)
  assert(type(result) == "table", "expected table")
  assert(#result == 2, "expected 2 elements")
  assert(result[1] == fn, "first element should be the function")
  assert(result[2] == "fallback", "second element should be 'fallback'")
end)

-- 测试 get_cmp_result
t("get_cmp_result: extracts newText", function()
  local entry = { textEdit = { newText = "你好" } }
  local result = cmp.get_cmp_result(entry)
  assert(result == "你好", "expected '你好'")
end)

t("get_cmp_result: nil for missing fields", function()
  assert(cmp.get_cmp_result({}) == nil, "expected nil")
  assert(cmp.get_cmp_result({ textEdit = {} }) == nil, "expected nil")
end)

-- 测试 get_input_code
t("get_input_code: extracts filterText", function()
  local entry = { filterText = "ni_hao" }
  assert(cmp.get_input_code(entry) == "ni_hao", "expected 'ni_hao'")
end)

-- 测试 get_cmp_source_name
t("get_cmp_source_name: extracts source_id", function()
  local entry = { source_id = "lsp" }
  assert(cmp.get_cmp_source_name(entry) == "lsp", "expected 'lsp'")
end)

t("get_cmp_source_name: nil entry returns nil", function()
  assert(cmp.get_cmp_source_name(nil) == nil, "expected nil")
end)

-- 测试 is_rime_entry
t("is_rime_entry: nil returns false", function()
  assert(cmp.is_rime_entry(nil) == false, "nil should be false")
end)

-- 测试 cmp_without_processing
t("cmp_without_processing: always returns true", function()
  assert(cmp.cmp_without_processing() == true, "expected true")
end)

-- 汇总
print(string.format("\n补全模块纯函数测试结果: %d 通过, %d 失败", passed, failed))
if failed > 0 then
  vim.cmd "cquit!"
end
