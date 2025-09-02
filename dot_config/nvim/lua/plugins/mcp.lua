-- Essential development tools (telescope, git, terminal)
-- Provides MCP-like functionality through proven plugins
return {
  -- File operations and search
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git status" },
    },
  },
  
  -- Git integration
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {},
  },
  
  -- Terminal integration
  {
    "akinsho/toggleterm.nvim",
    keys = {
      { "<C-\\>", "<cmd>ToggleTerm<cr>", desc = "Toggle terminal" },
    },
    opts = { direction = "horizontal" },
  },
}