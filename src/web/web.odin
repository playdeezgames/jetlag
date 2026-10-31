#+build js
// The thin browser layer. The page owns requestAnimationFrame and calls the exports below; saves go
// through the two imports. Everything with rules in it is in package game.
package main

import "base:runtime"
import "jl:game"

foreign import host "env"
@(default_calling_convention = "contextless")
foreign host {
	store_get :: proc(slot: i32) -> f64 ---
	store_set :: proc(slot: i32, value: f64) ---
	// The online scores live in the page (LootLocker); it answers through the platform_board_* exports.
	board_refresh :: proc() ---
	board_submit :: proc(score: i32) ---
}

// The page's save slots.
SLOT_HIGH :: 0
SLOT_BANK :: 1
SLOT_MUTED :: 2

g: game.Game
frame: game.Frame
scratch: [game.NAME_LEN]u8 // the page writes a name here before calling platform_board_add or platform_player_name

main :: proc() {
	g = game.new_game(1)
}

// Keeps odin.js from ending the program straight after main (see Tech/Odin wasm recipe).
@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	return true
}

@(export)
platform_init :: proc "c" (seed: f64) {
	context = runtime.default_context()
	g = game.new_game(u64(seed))
	g.high = int(store_get(SLOT_HIGH))
	g.bank = int(store_get(SLOT_BANK))
	g.muted = store_get(SLOT_MUTED) != 0
	game.render(&g, &frame)
}

@(export)
platform_frame :: proc "c" (dt: f64) {
	context = runtime.default_context()
	game.tick(&g, f32(min(dt, 0.25)))
	if score, ok := game.take_submit(&g); ok {
		g.board_status = .Loading
		board_submit(i32(score))
	}
	save_if_dirty()
	game.render(&g, &frame)
}

@(export)
platform_command :: proc "c" (c: i32) {
	context = runtime.default_context()
	if c < 0 || c > i32(max(game.Command)) {
		return
	}
	was := g.show_board
	game.command(&g, game.Command(c))
	if g.show_board && !was {
		refresh_board()
	}
	save_if_dirty()
}

@(export)
platform_scratch_ptr :: proc "c" () -> rawptr {
	return &scratch
}

// platform_board_begin clears the rows; the page then calls platform_board_add for each, then platform_board_status.
@(export)
platform_board_begin :: proc "c" () {
	context = runtime.default_context()
	game.board_begin(&g)
}

// platform_board_status takes a game.Board_Status (Ready after the rows, Failed when the request did not work).
@(export)
platform_board_status :: proc "c" (s: i32) {
	if s < 0 || s > i32(max(game.Board_Status)) {
		return
	}
	g.board_status = game.Board_Status(s)
}

// platform_board_add appends a row: the name is the first n bytes of the scratch buffer.
@(export)
platform_board_add :: proc "c" (score, n: i32) {
	context = runtime.default_context()
	game.board_add(&g, scratch[:clamp(int(n), 0, len(scratch))], int(score))
}

@(export)
platform_player_name :: proc "c" (n: i32) {
	context = runtime.default_context()
	game.set_entry(&g.player, scratch[:clamp(int(n), 0, len(scratch))], 0)
}

@(export)
platform_frame_ptr :: proc "c" () -> rawptr {
	return &frame
}

@(export)
platform_width :: proc "c" () -> i32 {
	return game.WIDTH
}

@(export)
platform_height :: proc "c" () -> i32 {
	return game.HEIGHT
}

@(export)
platform_in_play :: proc "c" () -> i32 {
	return g.in_play ? 1 : 0
}

// platform_take_sfx returns the next sound id to play, or -1.
@(export)
platform_take_sfx :: proc "c" () -> i32 {
	context = runtime.default_context()
	s, ok := game.take_sfx(&g)
	return ok ? i32(s) : -1
}

refresh_board :: proc() {
	g.board_status = .Loading
	board_refresh()
}

save_if_dirty :: proc() {
	if !g.dirty {
		return
	}
	g.dirty = false
	store_set(SLOT_HIGH, f64(g.high))
	store_set(SLOT_BANK, f64(g.bank))
	store_set(SLOT_MUTED, g.muted ? 1 : 0)
}
