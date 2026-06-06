--- rimels.utils - 向后兼容重新导出层
---
--- 拆分后，所有 require("rimels.utils") 的调用保持正常工作。
--- 新开发建议直接使用具体模块：
---   rimels.text  - 文本/光标工具函数
---   rimels.cmp   - 补全框架交互
---   rimels.lsp   - LSP 客户端管理

local M = {}

-- 逐模块加载并合并公开导出到同一命名空间
local function load_and_merge(module_name)
  local mod = require(module_name)
  for k, v in pairs(mod) do
    M[k] = v
  end
  return mod
end

load_and_merge "rimels.text"
load_and_merge "rimels.cmp"
load_and_merge "rimels.lsp"

-- 版本常量（直接定义以确保可靠性）
M.has_nvim_0_10_2 = vim.fn.has "nvim-0.10.2" == 1
M.has_nvim_0_11 = vim.fn.has "nvim-0.11.0" == 1

return M
