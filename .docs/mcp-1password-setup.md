# MCP 1Password Setup Guide

This document describes the 1Password items that need to be created to support the MCP configuration template.

## Required 1Password Items

The following items need to be created in the "Private" vault in 1Password:

### API Keys and Tokens
- **GitHub Personal Access Token** - credential field containing GitHub PAT
- **Anthropic API Key** - credential field containing Anthropic/Claude API key
- **Browserbase API Key** - credential field containing Browserbase API key
- **Browserbase Project ID** - credential field containing Browserbase project ID
- **Gemini API Key** - credential field containing Google Gemini API key
- **Smithery API Key** - credential field containing Smithery API key
- **Smithery Profile** - credential field containing Smithery profile name
- **EXA Search API Key** - credential field containing EXA Search API key
- **EXA Search Profile** - credential field containing EXA Search profile name

### Azure Configuration
- **Azure Client ID** - credential field containing Azure client ID
- **Azure Client Secret** - credential field containing Azure client secret
- **Azure Tenant ID** - credential field containing Azure tenant ID
- **Azure Subscription ID** - credential field containing Azure subscription ID

### Azure DevOps
- **Azure DevOps Organization** - credential field containing ADO organization name

### Search Services
- **OpenSearch Hosts** - credential field containing OpenSearch host URLs
- **OpenSearch Username** - credential field containing OpenSearch username
- **OpenSearch Password** - credential field containing OpenSearch password
- **Elasticsearch Hosts** - credential field containing Elasticsearch host URLs
- **Elasticsearch Username** - credential field containing Elasticsearch username
- **Elasticsearch Password** - credential field containing Elasticsearch password

## Template Features

### OS Detection
The template detects the operating system using `{{ .chezmoi.os }}` and provides different configurations:

- **Android (Termux)**: Uses `npx` commands since Docker is not available
- **Linux/Windows**: Uses Docker commands for better isolation

### Affected Servers
The following MCP servers have Android-specific npx alternatives:

1. **Azure Cloud**: 
   - Docker: `mcr.microsoft.com/azure-sdk/azure-mcp:latest`
   - NPX: `@azure/mcp-server@latest`

2. **GitHub**:
   - Docker: `ghcr.io/github/github-mcp-server`
   - NPX: `@modelcontextprotocol/server-github@latest`

3. **Context7**:
   - Docker: `context7-mcp`
   - NPX: `@upstash/context7-mcp@latest`

4. **OpenSearch**:
   - Docker/UV: `opensearch-mcp-server-py`
   - NPX: `opensearch-mcp-server@latest`

5. **ElasticSearch**:
   - Docker/UV: `uv` with specific args
   - NPX: `elasticsearch-mcp-server@latest`

Note: Some NPX package names are estimated and may need verification/correction based on actual availability.