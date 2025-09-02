#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Install AstroVim with minimal AI configuration
echo "Setting up AstroVim with AI extensions..."

# Install AstroVim using their official installer
if [ ! -d "$HOME/.config/nvim" ]; then
    echo "Installing AstroVim..."
    git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim
    rm -rf ~/.config/nvim/.git
else
    echo "AstroVim directory already exists, updating configurations..."
fi

# Create minimal environment configuration
if [ ! -f "$HOME/.config/nvim/.env" ]; then
    cat > "$HOME/.config/nvim/.env" << 'EOF'
# AI Provider API Keys - Uncomment and set your keys:
# ANTHROPIC_API_KEY=your_claude_api_key_here  
# OPENAI_API_KEY=your_openai_api_key_here
EOF
    echo "Created .env template for AI API keys"
fi

echo "AstroVim setup complete!"
echo "Configure API keys in ~/.config/nvim/.env for AI features"