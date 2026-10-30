#!/usr/bin/env bash
# Regenerates assets/screenshots/*.png and assets/cover.png from the game's own renderer (no browser needed).
# Needs Odin and Pillow. Usage: tools/shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN=${ODIN:-odin}
mkdir -p build/shots assets/screenshots
"$ODIN" test src/game -define:ODIN_TEST_THREADS=1 -define:JETLAG_SHOTS=true -define:ODIN_TEST_NAMES=game.test_bot_survives_a_while >/dev/null
rm -f odin game
python3 tools/make_cover.py
