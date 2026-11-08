#!/bin/sh
# Applies the Ask Tala identity to a built LibreChat client directory.
set -eu
dist="$1"
here="$(dirname "$0")"
index="$dist/index.html"
test -f "$index"

sed -i \
  -e 's|<title>[^<]*</title>|<title>Ask Tala</title>|' \
  -e 's|content="LibreChat[^"]*"|content="Ask Tala, the information helpdesk of the fictional Tala Ridge College"|' \
  -e 's|name="theme-color" content="[^"]*"|name="theme-color" content="#14304f"|' \
  -e 's|</head>|<link rel="stylesheet" href="brand.css" /></head>|' \
  "$index"
cp "$here/brand.css" "$dist/brand.css"

mkdir -p "$dist/assets"
cp "$here/logo.svg" "$dist/assets/logo.svg"
for icon in favicon-16x16.png favicon-32x32.png apple-touch-icon-180x180.png icon-192x192.png maskable-icon.png; do
  cp "$here/icons/$icon" "$dist/assets/$icon"
done

for manifest in "$dist"/manifest.webmanifest "$dist"/manifest.json; do
  if [ -f "$manifest" ]; then
    sed -i -e 's/"name":"[^"]*"/"name":"Ask Tala"/' -e 's/"short_name":"[^"]*"/"short_name":"Ask Tala"/' "$manifest"
    rm -f "$manifest.gz" "$manifest.br"
  fi
done
rm -f "$index.gz" "$index.br"
