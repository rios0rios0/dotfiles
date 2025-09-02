-- Minimal AstroNvim user configuration
return {
  -- Essential keymaps for AI features
  polish = function()
    local map = vim.keymap.set
    
    -- AI assistance keymaps
    map("n", "<leader>aa", function() require("avante.api").ask() end, { desc = "Ask AI" })
    map("v", "<leader>ex", function() require("avante.api").edit() end, { desc = "Explain code" })
    map("n", "<C-a>", function() require("avante").toggle() end, { desc = "Toggle AI chat" })
  end,
}