#!/bin/bash
# Split current AeroSpace workspace and open clipboard URL in browser.
url=$(pbpaste)
if [[ "$url" =~ ^https?:// ]]; then
  aerospace split horizontal
  open "$url"
else
  echo "Clipboard does not contain a URL: $url" >&2
  exit 1
fi
