-- AstroNvim Community plugins configuration
-- This file configures community plugins for AstroNvim

return {
  -- Add community plugins here
  "AstroNvim/astrocommunity",
  
  -- Language support packs
  { import = "astrocommunity.pack.lua" },
  { import = "astrocommunity.pack.python" },
  { import = "astrocommunity.pack.javascript" },
  { import = "astrocommunity.pack.typescript" },
  { import = "astrocommunity.pack.json" },
  { import = "astrocommunity.pack.yaml" },
  { import = "astrocommunity.pack.markdown" },
  { import = "astrocommunity.pack.bash" },
  { import = "astrocommunity.pack.go" },
  { import = "astrocommunity.pack.rust" },
  
  -- AI and completion enhancements
  { import = "astrocommunity.completion.copilot-lua" },
  
  -- Git enhancements
  { import = "astrocommunity.git.git-blame-nvim" },
  
  -- Utility plugins
  { import = "astrocommunity.utility.noice-nvim" },
  { import = "astrocommunity.motion.leap-nvim" },
}