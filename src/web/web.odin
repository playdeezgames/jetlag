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
}

// The page's save slots.
SLOT_HIGH :: 0
SLOT_BANK :: 1
SLOT_MUTED :: 2

g: game.Game
frame: game.Frame

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
	save_if_dirty()
	game.render(&g, &frame)
}

@(export)
platform_command :: proc "c" (c: i32) {
	context = runtime.default_context()
	if c < 0 || c > i32(max(game.Command)) {
		return
	}
	game.command(&g, game.Command(c))
	save_if_dirty()
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

save_if_dirty :: proc() {
	if !g.dirty {
		return
	}
	g.dirty = false
	store_set(SLOT_HIGH, f64(g.high))
	store_set(SLOT_BANK, f64(g.bank))
	store_set(SLOT_MUTED, g.muted ? 1 : 0)
}
