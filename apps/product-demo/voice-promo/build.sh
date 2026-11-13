#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ -d node_modules ] || npm ci --workspaces=false
npx remotion browser ensure
npm run promo:audio
npm run promo:render
npm run promo:verify
