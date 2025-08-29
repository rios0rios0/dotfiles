-- AstroNvim user configuration with AI and MCP enhancements
-- This file provides additional user customizations

local config = {
  
  -- Configure AstroNvim updates
  updater = {
    remote = "origin", -- remote to use
    channel = "stable", -- "stable" or "nightly"
    version = "latest", -- "latest", tag name, or regex search like "v1.*" to only do updates before v2 (STABLE ONLY)
    branch = "nightly", -- branch name (NIGHTLY ONLY)
    commit = nil, -- commit hash (NIGHTLY ONLY)
    pin_plugins = nil, -- nil, true, false (nil will pin plugins on stable only)
    skip_prompts = false, -- skip prompts about breaking changes
    show_changelog = true, -- show the changelog after performing an update
    auto_quit = false, -- automatically quit the current session after a successful update
    remotes = { -- easily add new remotes to track
      --   ["remote_name"] = "https://remote_url.come/repo.git", -- full remote url
      --   ["remote2"] = "github_user/repo", -- GitHub user/repo shortcut,
      --   ["remote3"] = "github_user", -- GitHub user assume AstroNvim fork
    },
  },

  -- Set colorscheme to use
  colorscheme = "astrodark",

  -- Diagnostics configuration (disabled by default)
  -- diagnostics = {
  --   virtual_text = true,
  --   underline = true,
  -- },

  lsp = {
    -- customize lsp formatting options
    formatting = {
      -- control auto formatting on save
      format_on_save = {
        enabled = true, -- enable or disable format on save globally
        allow_filetypes = { -- enable format on save for specified filetypes only
          -- "go",
        },
        ignore_filetypes = { -- disable format on save for specified filetypes
          -- "python",
        },
      },
      disabled = { -- disable formatting capabilities for the listed language servers
        -- disable lua_ls formatting capability if you want to use StyLua to format your lua code
        -- "lua_ls",
      },
      timeout_ms = 1000, -- default format timeout
      -- filter = function(client) -- fully override the default formatting function
      --   return true
      -- end
    },
    -- enable servers that you already have installed without mason
    servers = {
      -- "pyright"
    },
  },

  -- Configure require("lazy").setup() options
  lazy = {
    defaults = { lazy = true },
    performance = {
      rtp = {
        -- customize default disabled vim plugins
        disabled_plugins = { "tohtml", "gzip", "matchit", "zipPlugin", "netrwPlugin", "tarPlugin" },
      },
    },
  },

  -- This function is run last and is a good place to configuring
  -- augroups/autocommands and custom filetypes also this just pure lua so
  -- anything that doesn't fit in the normal config locations above can go here
  polish = function()
    -- Set up custom filetypes
    vim.filetype.add {
      extension = {
        foo = "fooscript",
      },
      filename = {
        ["Foofile"] = "fooscript",
      },
      pattern = {
        ["~/%.config/foo/.*"] = "fooscript",
      },
    }

    -- Custom autocmds for AI enhancements
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "python", "javascript", "typescript", "lua", "go", "rust" },
      callback = function()
        -- Enable AI suggestions for code files
        vim.opt_local.spell = false
        vim.opt_local.wrap = false
      end,
    })

    -- Auto-save configuration for better AI workflow
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      callback = function()
        if vim.bo.modified and vim.bo.buftype == "" and vim.fn.expand("%") ~= "" then
          vim.cmd("silent! update")
        end
      end,
    })

    -- Custom keymaps for AI features
    local map = vim.keymap.set
    
    -- Avante keymaps
    map("n", "<leader>aa", function() require("avante.api").ask() end, { desc = "Avante: Ask AI" })
    map("v", "<leader>ae", function() require("avante.api").edit() end, { desc = "Avante: Edit selection" })
    map("n", "<leader>ar", function() require("avante.api").refresh() end, { desc = "Avante: Refresh" })
    map("n", "<leader>af", function() require("avante.api").focus() end, { desc = "Avante: Focus chat" })
    
    -- MCP keymaps (additional to plugin config)
    map("n", "<leader>mf", function() require("mcp-tools").call_tool("filesystem", "list_files", { path = vim.fn.getcwd() }) end, { desc = "MCP: List files" })
    map("n", "<leader>mg", function() require("mcp-tools").call_tool("git", "get_status") end, { desc = "MCP: Git status" })
    
    -- Quick AI chat toggle
    map("n", "<C-a>", "<cmd>MCPChatToggle<cr>", { desc = "Toggle AI Chat" })
    
    -- AI code explanation
    map("v", "<leader>ex", function()
      local selection = vim.fn.getline("'<", "'>")
      require("mcp-chat").ask("Explain this code: " .. table.concat(selection, "\n"))
    end, { desc = "Explain selected code" })
  end,
}

return config