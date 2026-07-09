# qmd

Config for [qmd](https://github.com/tobi/qmd) (tobilu/qmd) — an on-device
hybrid search engine for markdown, docs, and notes. Combines BM25 full-text,
vector semantic, and LLM re-ranking, all local via GGUF models.

## Setup

Installed by `cli/setup.sh` (npm global + Homebrew sqlite). `scripts/link.sh`
symlinks `index.yml` to `~/.config/qmd/index.yml`.

## Usage

```sh
qmd collection add ~/notes --name notes
qmd context add qmd://notes "Personal notes"
qmd embed
qmd search "project timeline"
qmd query "quarterly planning"   # hybrid + rerank (best quality)
qmd status
```

## MCP

Expose qmd to AI agents over MCP:

```sh
qmd mcp          # stdio (Claude Code / pi can launch as subprocess)
qmd mcp --http    # HTTP daemon on localhost:8181
```

Claude Code config is wired in `claude/settings.json` (mcpServers.qmd).