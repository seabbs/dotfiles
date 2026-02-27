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

## REPL (vim-slime → tmux)

Sends code from Neovim to the bottom-right tmux pane (where your REPL lives).
Works with any REPL (R, Julia, Python) — slime just sends text to tmux.

### Sending code

| Key | Mode | Action |
|---|---|---|
| `<leader>sc` | normal | Send current line |
| `<leader>sc` | visual | Send selection |
| `<leader>sp` | normal | Send paragraph |
| `<leader>sf` | normal | Send entire file |
| `<leader>su` | normal | Send from start to cursor |
| `<leader>sF` | normal | Send function (treesitter) |
| `<leader>sb` | normal | Send code block (Quarto/Rmd) |
| `<leader>sa` | normal | Send all code blocks (Quarto/Rmd) |
| `<leader>sU` | normal | Send code blocks up to cursor (Quarto/Rmd) |

### R-specific

| Key | Action |
|---|---|
| `<leader>so` | Start httpgd plot server |

### Configuration

| Key | Action |
|---|---|
| `<leader>s=` | Reconfigure target pane |

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
| `<leader>cjs` | Send Pkg.test() to REPL |

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
| `<leader>?` | Searchable keybinding cheatsheet |
| `<leader>:` | All commands |
| `<leader>;` | Command history |
| `<leader>fF` | Frequent files (frecency) |
| `<leader>cm` | Molten commands |
| `<leader>cq` | Quarto commands |

## Troubleshooting

**Slime not sending to correct pane:**
Press `<leader>s=` to reconfigure. Use `{bottom-right}` for standard layout.
Run `tmux display-panes` (or prefix + q) to see pane numbers.

**LSP not working:**
R: verify `languageserver` package is installed.
Julia: run `:checkhealth lsp`.
Python: Mason should auto-install.

**Code block keybindings not working:**
`<leader>sb`, `<leader>sa`, `<leader>sU` only work in `.rmd`, `.qmd`, and `.md` files.
Check filetype with `:set filetype?`.

**Plots not showing:**
R: run `<leader>so` to start httpgd.
Julia: GUI backends (GR, GLMakie) open native macOS windows.
Python: use `plt.show()` or save to file.
