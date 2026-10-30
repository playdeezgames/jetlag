# CLAUDE.md

JetLag: an Odin game that targets `js_wasm32` (GitHub Pages) and nothing else. The shared knowledge is in the private vault `/home/yermom/git/bok-of-splorr` (`splorr/Games/JetLag.md`, `Tech/Odin wasm recipe.md`, `Tech/Release standard.md`). Read the vault's `Home.md` standing rules first.

## Layout

- `src/game/`: pure rules (`game.odin`), software renderer (`render.odin`), baked m5x7 font (`font_data.odin`, generated), tests (`game_test.odin`, `#+build !js`).
- `src/web/web.odin`: `#+build js`; exports `platform_*`, imports `store_get`/`store_set`. Reached with `-collection:jl=src`.
- `web/index.html`: the loop, keyboard, touch, gamepad, Web Audio and localStorage. The `Command` and `Sound` enums in `src/game` must match its `CMD` and `SOUND_FILES`.
- `tools/pages.sh` builds `docs/` (served by Pages from `main`); `tools/shots.sh` makes screenshots and the cover; `gen_font.py` and `gen_sfx.py` are generators.

## Rules

- Do not push, enable Pages, or ship to itch.io unless the user says so ("push" is `git push`; "ship" is itch.io).
- Do not describe or "fix" the deliberate design as a problem: one charm per row, the triangular turn score, money lost on a crash.
- Anything an AI agent posts on itch.io must say it was posted by an AI agent.
- This replaces JetLag 2020 and JetLag 2023. Do not delete those repos or itch pages; that is the user's call.
