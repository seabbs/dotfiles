-- nvim-lspconfig's default cmd (`R --no-echo -e "languageserver::run()"`)
-- is correct and used as-is; it needs the `languageserver` R package in
-- the system library (install.packages("languageserver")). Mason also
-- ships an r-languageserver package, but its bundled library is missing
-- `collections` and its wrapper dies on startup, so don't point at it.
--
-- Only the filetype list is overridden. lspconfig defaults to
-- { "r", "rmd", "quarto" }, which attaches the R server to the whole .qmd
-- buffer and lints the prose as R. otter.nvim already exposes R chunks
-- through a hidden `.otter.R` buffer with filetype `r`, so `r` alone
-- covers .qmd and .Rmd chunks without the false positives.
return {
  filetypes = { "r", "rmd" },
}
