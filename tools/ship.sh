#!/usr/bin/env bash
# Prepares the itch.io build: tests, a size-optimised web build, a zip. Pushes ONLY with --push. Never commits,
# never deletes anything but its own zip. Usage: tools/ship.sh [--push]
#
# The target is the existing "JetLag 2021" page (do not rename or add channels to a live page by accident).
# It is empty until the page's real slug and html channel are confirmed (Coxswain task 348); --push refuses until then.
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN=${ODIN:-odin}
TARGET="" # e.g. thegrumpygamedev/<slug>:html, once confirmed
ZIP="build/jetlag-html5.zip"

"$ODIN" test src/game -define:ODIN_TEST_THREADS=1
rm -f odin game # the test run can leave a stray binary
ODIN="$ODIN" OPT=size ./build.sh
rm -f "$ZIP"
(cd build/web && zip -q -9 -r "../jetlag-html5.zip" .) # index.html at the zip's root
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1)); wasm $(du -h build/web/game.wasm | cut -f1)"
unzip -l "$ZIP" | tail -8

if [[ "${1:-}" == "--push" ]]; then
	if [[ -z "$TARGET" ]]; then
		echo "refusing to push: TARGET is not set in tools/ship.sh (confirm the JetLag 2021 page slug and html channel first)" >&2
		exit 1
	fi
	if [[ -n "$(git status --porcelain)" ]]; then echo "note: the working tree has uncommitted changes; what is pushed is the working tree, not a commit"; fi
	butler push build/web "$TARGET"
	echo "pushed to $TARGET. It goes live after itch.io processes it; check: butler status $TARGET"
else
	echo "not pushed (run tools/ship.sh --push when you want it live; target: ${TARGET:-<not set yet>})"
fi
