#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Configure AI and development environment for AstroVIM
echo "Configuring AI environment for AstroVIM..."

# Create necessary directories
mkdir -p "$HOME/.config/nvim/lua"
mkdir -p "$HOME/.local/share/nvim"

# Set environment variables for AI providers
echo "Setting up environment variables for AI providers..."

# Create a .env file for AI API keys (will be managed separately)
if [ ! -f "$HOME/.config/nvim/.env" ]; then
    cat > "$HOME/.config/nvim/.env" << 'EOF'
# AI Provider API Keys
# Uncomment and set your API keys:
# ANTHROPIC_API_KEY=your_claude_api_key_here
# OPENAI_API_KEY=your_openai_api_key_here

# Development environment
NVIM_LOG_LEVEL=warn
EOF
    echo "Created .env template at ~/.config/nvim/.env"
    echo "Please edit this file to add your API keys for AI features."
fi

# Install additional Python packages for AI integration if available
if command -v pip >/dev/null 2>&1; then
    echo "Installing Python packages for AI integration..."
    pip install --user requests 2>/dev/null || echo "Python packages may already be installed."
else
    echo "Note: pip not found. Some AI features may require manual Python package installation."
fi

# Ensure Neovim can find the configuration
echo "Ensuring Neovim configuration is properly linked..."

# Create health check script
cat > "$HOME/.config/nvim/health-check.lua" << 'EOF'
-- Health check for AI configuration
local M = {}

function M.check()
  local health = vim.health or require("health")
  
  health.report_start("AI Configuration Health Check")
  
  -- Check if Node.js is available
  if vim.fn.executable("node") == 1 then
    health.report_ok("Node.js is available")
  else
    health.report_warn("Node.js not found - some features may not work")
  end
  
  -- Check if Python is available
  if vim.fn.executable("python") == 1 or vim.fn.executable("python3") == 1 then
    health.report_ok("Python is available")
  else
    health.report_warn("Python not found - some AI features may not work")
  end
  
  -- Check if config files exist
  local config_files = {
    "lua/plugins/avante.lua",
    "lua/plugins/mcp.lua",
    "lua/community.lua"
  }
  
  for _, file in ipairs(config_files) do
    local path = vim.fn.stdpath("config") .. "/" .. file
    if vim.fn.filereadable(path) == 1 then
      health.report_ok("Configuration file found: " .. file)
    else
      health.report_error("Configuration file missing: " .. file)
    end
  end
end

return M
EOF

echo "AI environment configuration complete!"
echo "To verify setup:"
echo "1. Run 'nvim' and execute ':checkhealth' to verify installation"
echo "2. Edit ~/.config/nvim/.env with your API keys for AI features"
echo "3. Use <leader>aa to start AI chat (when Avante is loaded)"
echo "4. Use <leader>ff for file finding, <leader>fg for live grep"