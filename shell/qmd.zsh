# qmd (tobilu/qmd) — on-device hybrid search for markdown/docs
# Config: ~/.config/qmd/index.yml  |  Index: ~/.cache/qmd/index.sqlite

# Quick searches
alias qmds='qmd search'
alias qmdv='qmd vsearch'        # vector / semantic
alias qmdq='qmd query'          # hybrid + rerank (best quality)
alias qmdg='qmd get'

# Index maintenance
alias qmdu='qmd update'         # re-index all collections
alias qmde='qmd embed'           # generate embeddings
alias qmdst='qmd status'

# MCP server (background HTTP daemon on :8181)
alias qmd-mcp='qmd mcp --http --daemon'
alias qmd-mcp-stop='qmd mcp stop'