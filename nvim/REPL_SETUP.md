# Neovim setup

LazyVim-based configuration for R, Julia, and Python development.

## Prerequisites

**R:**
```r
install.packages("languageserver")
install.packages("httpgd")
```
Also install radian: `pip install radian`

**Julia:**
```julia
using Pkg
Pkg.add("LanguageServer")
```

**Python:**
Mason auto-installs `basedpyright` on first use.

## REPL (iron.nvim)

### Management

| Key | Action |
|---|---|
| `<leader>rs` | Toggle REPL (auto-detects filetype) |
| `<leader>rr` | Restart REPL |
| `<leader>rf` | Focus REPL |
| `<leader>rh` | Hide REPL (keeps process) |
| `<leader>rk` | Kill REPL (terminate) |

### Language-specific REPLs

| Key | Action |
|---|---|
| `<leader>rj` | Start Julia REPL |
| `<leader>rR` | Start R REPL |
| `<leader>rp` | Start Python REPL |

### Sending code

| Key | Mode | Action |
|---|---|---|
| `<leader>sc` | normal | Send current line |
| `<leader>sc` | visual | Send selection |
| `<leader>sf` | normal | Send entire file |
| `<leader>sp` | normal | Send paragraph |
| `<leader>sF` | normal | Send function block |
| `<leader>su` | normal | Send from start to cursor |
| `<leader>sb` | normal | Send code block (Quarto/Rmd) |
| `<leader>sa` | normal | Send all code blocks (Quarto/Rmd) |

### Marks

| Key | Action |
|---|---|
| `<leader>sm` | Mark function for repeated execution |
| `<leader>s<cr>` | Send marked region |
| `<leader>sd` | Remove mark |

### R-specific

| Key | Action |
|---|---|
| `<leader>so` | Start httpgd plot server |

## Testing (neotest)

Unified test runner with adapters for R (testthat), Python (pytest), and Julia (Pkg.test).

| Key | Action |
|---|---|
| `<leader>tr` | Run nearest test |
| `<leader>tt` | Run current file |
| `<leader>tT` | Run all test files |
| `<leader>tl` | Run last test |
| `<leader>ts` | Toggle summary panel |
| `<leader>to` | Show test output |
| `<leader>tO` | Toggle output panel |
| `<leader>tS` | Stop running test |
| `<leader>tw` | Toggle file watch |
| `<leader>ta` | Attach to test |
| `<leader>td` | Debug nearest test |

### Julia-specific

| Key | Action |
|---|---|
| `<leader>cji` | Open Julia REPL (terminal) |
| `<leader>cjs` | Send Pkg.test() to iron REPL |

## Highlight (vim-illuminate)

Automatically highlights other uses of the word under the cursor using LSP, treesitter, and regex.

| Key | Action |
|---|---|
| `]]` | Next reference |
| `[[` | Previous reference |
| `<leader>ux` | Toggle illuminate on/off |

## Pinned files (harpoon)

Quick-switch between a small set of working files.

| Key | Action |
|---|---|
| `<leader>ha` | Add current file to harpoon |
| `<leader>hh` | Open harpoon menu |
| `<leader>1`-`4` | Jump to pinned file 1-4 |
| `<leader>hp` | Previous pinned file |
| `<leader>hn` | Next pinned file |

## Undo tree

Visual undo history browser. Navigate branches of changes and restore any state.

| Key | Action |
|---|---|
| `<leader>uu` | Toggle undo tree |

## Quarto / Molten

### Quarto runner (molten)

| Key | Action |
|---|---|
| `\rc` | Run cell |
| `\ra` | Run cell and above |
| `\rA` | Run all cells |
| `\rl` | Run line |
| `\r` (visual) | Run visual range |
| `\qp` | Quarto preview |
| `\qq` | Close Quarto preview |

### Molten kernel

| Key | Action |
|---|---|
| `\mi` | Init Molten |
| `\el` | Evaluate line |
| `\e` (visual) | Evaluate visual |
| `\ec` | Evaluate cell |
| `\rr` | Re-evaluate cell |
| `\mr` | Restart kernel |
| `\md` | Delete kernel |
| `\jj` | Start Julia kernel |
| `\jr` | Start R kernel |
| `\jp` | Start Python kernel |
| `\ja` | Activate Julia project |
| `\jd` | Activate Julia docs env |

## Notes (Obsidian)

| Key | Action |
|---|---|
| `<leader>nn` | New note |
| `<leader>no` | Open in Obsidian |
| `<leader>ns` | Switch note |
| `<leader>nf` | Search notes |
| `<leader>nd` | Today's daily note |
| `<leader>nD` | Browse daily notes |
| `<leader>nb` | Backlinks |
| `<leader>nt` | Tags |
| `<leader>nl` | Links in buffer |
| `<leader>nT` | Insert template |
| `<leader>np` | Paste image |
| `<leader>nr` | Rename note |
| `<leader>nm` | Open Meta/TODO |

## GitHub (Octo)

| Key | Action |
|---|---|
| `<leader>oi` | List issues |
| `<leader>oI` | Search issues |
| `<leader>op` | List PRs |
| `<leader>oP` | Search PRs |
| `<leader>or` | List repos |
| `<leader>oS` | Search |
| `<leader>oci` | Create issue |
| `<leader>ocp` | Create PR |

## AI

| Key | Action |
|---|---|
| `<leader>ac` | Toggle Claude Code |
| `<leader>af` | Focus Claude |
| `<leader>ar` | Resume Claude |
| `<leader>aC` | Continue Claude |
| `<leader>am` | Select Claude model |
| `<leader>ab` | Add current buffer to Claude |
| `<leader>as` (visual) | Send selection to Claude |
| `<leader>aa` | Accept diff |
| `<leader>ad` | Deny diff |

## LaTeX

| Key | Action |
|---|---|
| `<leader>mn` | LaTeX equation preview (popup) |
| `<leader>mN` | Toggle inline LaTeX rendering |

## Command discovery

| Key | Action |
|---|---|
| `<leader>:` | All commands |
| `<leader>;` | Command history |
| `<leader>cm` | Molten commands |
| `<leader>cq` | Quarto commands |

## Troubleshooting

**R REPL not starting:**
Check radian is installed (`pip install radian`).
Falls back to `R` if not found.

**LSP not working:**
R: verify `languageserver` package is installed.
Julia: run `:checkhealth lsp`.
Python: Mason should auto-install.

**Code block keybindings not working:**
`<leader>sb` and `<leader>sa` only work in `.rmd` and `.qmd` files.
Check filetype with `:set filetype?`.

**Plots not showing:**
R: run `<leader>so` to start httpgd.
Julia: use PlotlyJS or Plots with browser backend.
Python: use `plt.show()` or save to file.
