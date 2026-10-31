# JetLag

A scrolly-block endless runner. A jet sits at the top of the screen while the board scrolls up past it, leaving a six-cell tail above it. Steer left and right between the blocks. The longer you hold a line before you turn, the more the turn scores.

**Play: https://playdeezgames.github.io/jetlag/**

This one game replaces two earlier versions: JetLag 2020 (Defold, Lua) and JetLag 2023 (a TIC-80 cart). It keeps the 2020 rules, a 40 by 30 grid and a triangular score for each straight run, and adds the 2023 charms: coins to collect, and green banks that deposit them for good.

## Rules

- Left / Right, A / D, or tap the left or right half of the screen to turn. Z, Space, Enter or a tap starts a run. M mutes.
- Hitting a wall or a white block ends the run.
- A turn scores `run * (run + 1) / 2`, where `run` is the ticks since your last turn. Turning the way you already face does nothing.
- Each new row holds one charm: a block (90%), a coin (9%) or a bank (1%). A coin is worth $1 for this run. Hit a bank to move the run's money into your bank. Crash with money in hand and it is lost.
- The high score, the bank and mute are saved in the browser.

## Build

Odin (`dev-2026-07` or newer), Python 3 with Pillow for the generators.

```bash
odin test src/game -define:ODIN_TEST_THREADS=1   # rules and renderer, native
./build.sh                                        # build/web (serve with: python3 -m http.server -d build/web)
tools/pages.sh                                    # tests, size build, copies it into docs/ for GitHub Pages
tools/shots.sh                                    # screenshots and cover from the game's own renderer
```

`src/game` is pure (rules, a software renderer, baked font); `src/web` is the thin browser layer; `web/index.html` owns the loop, input, sound and saving.

## Credits

- Game by TheGrumpyGameDev (SPLORR!!). Ported to Odin and wasm with an AI agent, Claude Code, at the author's direction.
- Font: m5x7 by Daniel Linssen (managore), CC0.
- Turn and crash sounds are from the original JetLag; the coin and bank blips are synthesised by `tools/gen_sfx.py`.
- The old versions: https://github.com/playdeezgames/JetLag2020 and https://github.com/playdeezgames/jetlag2023.
