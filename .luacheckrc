-- Lint configuration for zcmp.nvim.
-- Warning reference: https://luacheck.readthedocs.io/en/stable/warnings.html

std = "luajit"
codes = true

-- zcmp runs inside Neovim; `vim` is an injected global. Writable rather than
-- read-only because configuring completion *is* writing options: `vim.go`,
-- `vim.bo` and `vim.opt` are how 'complete', 'completeopt' and 'autocomplete'
-- are set.
globals = { "vim" }

-- The project has no line-length convention (no stylua/editorconfig). luacheck
-- here guards correctness — unused/shadowed vars, undefined globals — not
-- formatting, so the line-length check is left off.
max_line_length = false

-- The suite runs under busted (describe/it/assert globals) and writes to
-- vim.* to stage buffer, option and keymap state. Unused-variable warnings are
-- left on: the suite is clean without suppressing them, and an unused require
-- or a stub that quietly stopped being called is worth hearing about.
files["tests"] = {
  std = "luajit+busted",
  globals = { "vim", "_G" },
}
