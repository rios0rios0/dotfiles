# AstroVIM AI Configuration for Android

This configuration transforms NeoVIM into a Cursor-like AI-powered editor on Android (Termux).

## Features

### AI-Powered Coding Assistant (Avante.nvim)
- **Chat Interface**: AI-powered coding assistance similar to Cursor
- **Code Generation**: Generate code based on natural language descriptions
- **Code Explanation**: Explain selected code snippets
- **Code Editing**: AI-assisted code modifications

### Enhanced Development Tools
- **File Operations**: Advanced file searching and browsing
- **Git Integration**: Visual git status, staging, and history
- **Terminal Integration**: Built-in terminal for command execution
- **Search & Replace**: Powerful search across project files

## Key Mappings

### AI Features
- `<leader>aa` - Ask AI for assistance
- `<leader>ae` - Edit selection with AI (visual mode)
- `<leader>ar` - Refresh AI chat
- `<leader>af` - Focus AI chat window
- `<C-a>` - Quick toggle AI chat
- `<leader>ex` - Explain selected code (visual mode)

### File Operations (MCP-like functionality)
- `<leader>ff` - Find files
- `<leader>fg` - Live grep search
- `<leader>fb` - Find buffers
- `<leader>fr` - Recent files
- `<leader>fc` - Commands
- `<leader>mt` - File browser

### Git Integration
- `<leader>gs` - Git status
- `<leader>gc` - Git commits
- `<leader>gb` - Git branches
- `<leader>mg` - Preview git hunk
- `<leader>mr` - Reset git hunk
- `<leader>ms` - Stage git hunk
- `<leader>md` - Git diff

### Terminal & Search
- `<C-\>` - Toggle terminal
- `<leader>mf` - File operations terminal
- `<leader>sr` - Replace in files
- `<leader>sw` - Search current word
- `<leader>sp` - Search in current file

## Setup Instructions

1. **Apply dotfiles**:
   ```bash
   chezmoi init --apply rios0rios0
   ```

2. **Configure API Keys**:
   Edit `~/.config/nvim/.env` and add your API keys:
   ```bash
   ANTHROPIC_API_KEY=your_claude_api_key_here
   OPENAI_API_KEY=your_openai_api_key_here
   ```

3. **Verify Installation**:
   ```bash
   nvim
   :checkhealth
   ```

4. **Install Plugins**:
   When you first open Neovim, plugins will automatically install.

## Configuration Files

- `~/.config/nvim/lua/plugins/avante.lua` - AI assistant configuration
- `~/.config/nvim/lua/plugins/mcp.lua` - Enhanced development tools
- `~/.config/nvim/lua/community.lua` - Community plugins
- `~/.config/nvim/lua/config/user.lua` - User customizations

## Troubleshooting

1. **Plugin Installation Issues**:
   ```bash
   nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
   ```

2. **Missing Dependencies**:
   ```bash
   npm install -g tree-sitter-cli typescript typescript-language-server
   ```

3. **AI Features Not Working**:
   - Verify API keys in `~/.config/nvim/.env`
   - Check internet connectivity
   - Ensure Node.js and npm are installed

4. **Health Check**:
   ```bash
   nvim -c ':checkhealth'
   ```

## Supported AI Providers

- **Claude (Anthropic)**: Default provider, recommended for code assistance
- **OpenAI GPT-4**: Alternative provider for code generation
- **Local Models**: Can be configured for offline usage

## Tips

- Use visual mode selection before calling AI functions for context
- The AI chat window can be resized and moved
- Git integration works best in Git repositories
- File search respects `.gitignore` patterns
- Terminal can be used for running tests and build commands