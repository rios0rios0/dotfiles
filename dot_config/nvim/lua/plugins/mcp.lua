-- MCP (Model Context Protocol) configuration
-- Enables integration with various MCP servers and tools

return {
  -- Simple MCP integration plugin
  {
    "nvim-lua/plenary.nvim",
    lazy = false,
  },
  
  -- File operations and Git integration
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      defaults = {
        -- Configure telescope for better file searching (MCP-like functionality)
        file_ignore_patterns = { "node_modules", ".git/" },
        layout_config = {
          horizontal = {
            preview_width = 0.6,
          },
        },
      },
      extensions = {
        -- File browser extension
        file_browser = {
          theme = "ivy",
          hijack_netrw = true,
        },
      },
    },
    config = function(_, opts)
      require("telescope").setup(opts)
      
      -- Load extensions
      require("telescope").load_extension("file_browser")
      
      -- Set up keymaps for MCP-like functionality
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
      vim.keymap.set("n", "<leader>fr", builtin.oldfiles, { desc = "Recent files" })
      vim.keymap.set("n", "<leader>fc", builtin.commands, { desc = "Commands" })
      
      -- Git integration keymaps
      vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Git status" })
      vim.keymap.set("n", "<leader>gc", builtin.git_commits, { desc = "Git commits" })
      vim.keymap.set("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })
      
      -- File browser keymap
      vim.keymap.set("n", "<leader>mt", ":Telescope file_browser<CR>", { desc = "MCP: File browser" })
    end,
  },
  
  -- Enhanced file browser
  {
    "nvim-telescope/telescope-file-browser.nvim",
    dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  },
  
  -- Git integration
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
        untracked = { text = "┆" },
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        
        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end
        
        -- Git operations (MCP-like functionality)
        map("n", "<leader>mg", gs.preview_hunk, { desc = "MCP: Preview git hunk" })
        map("n", "<leader>mr", gs.reset_hunk, { desc = "MCP: Reset git hunk" })
        map("n", "<leader>ms", gs.stage_hunk, { desc = "MCP: Stage git hunk" })
        map("n", "<leader>mu", gs.undo_stage_hunk, { desc = "MCP: Undo stage hunk" })
        map("n", "<leader>md", gs.diffthis, { desc = "MCP: Git diff" })
      end,
    },
  },
  
  -- Terminal integration for command execution
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = {
      size = 20,
      open_mapping = [[<C-\>]],
      hide_numbers = true,
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      insert_mappings = true,
      persist_size = true,
      direction = "horizontal",
      close_on_exit = true,
      shell = vim.o.shell,
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)
      
      -- Create terminal commands for MCP-like functionality
      local Terminal = require("toggleterm.terminal").Terminal
      
      -- File operations terminal
      local file_ops = Terminal:new({
        cmd = "bash",
        dir = "git_dir",
        direction = "float",
        float_opts = {
          border = "double",
        },
        on_open = function(term)
          vim.cmd("startinsert!")
          vim.api.nvim_buf_set_keymap(term.bufnr, "n", "q", "<cmd>close<CR>", {noremap = true, silent = true})
        end,
      })
      
      function _file_ops_toggle()
        file_ops:toggle()
      end
      
      -- Create keymap for file operations
      vim.keymap.set("n", "<leader>mf", "<cmd>lua _file_ops_toggle()<CR>", { desc = "MCP: File operations terminal" })
    end,
  },
  
  -- Enhanced search capabilities
  {
    "nvim-pack/nvim-spectre",
    build = false,
    cmd = "Spectre",
    opts = { open_cmd = "noswapfile vnew" },
    keys = {
      { "<leader>sr", function() require("spectre").open() end, desc = "Replace in files (Spectre)" },
      { "<leader>sw", function() require("spectre").open_visual({select_word=true}) end, desc = "Search current word" },
      { "<leader>sp", function() require("spectre").open_file_search({select_word=true}) end, desc = "Search on current file" },
    },
  },
}