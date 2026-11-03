#+build !js
package game

import "core:testing"

started :: proc(seed: u64 = 1) -> Game {
	g := new_game(seed)
	command(&g, .Start)
	return g
}

// clear_ahead removes every charm so a test controls what the jet meets.
clear_charms :: proc(g: ^Game) {
	g.charms = {}
}

// step_clean steps with no new charm: the test sets the charm in the head row after scrolling.
place_next :: proc(g: ^Game, charm: Charm, column: i8) {
	// the charm that will reach the head row after the next step is the one in row HEAD_ROW+1 now
	g.charms[HEAD_ROW + 1] = charm
	g.columns[HEAD_ROW + 1] = column
}

@(test)
test_start_resets_and_plays :: proc(t: ^testing.T) {
	g := new_game(5)
	testing.expect(t, !g.in_play)
	command(&g, .Start)
	testing.expect(t, g.in_play)
	testing.expect_value(t, g.direction, 1)
	for i in 0 ..< TAIL_LENGTH {
		testing.expect_value(t, g.tail[i], i8(COLUMNS / 2 - 1))
	}
}

@(test)
test_tail_follows_head :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	for _ in 0 ..< 3 {
		step(&g)
		clear_charms(&g)
	}
	// head moved right three, tail trails one column behind per segment
	testing.expect_value(t, g.tail[0], i8(COLUMNS / 2 - 1 + 3))
	testing.expect_value(t, g.tail[1], i8(COLUMNS / 2 - 1 + 2))
	testing.expect_value(t, g.tail[3], i8(COLUMNS / 2 - 1))
}

@(test)
test_wall_crashes :: proc(t: ^testing.T) {
	g := started()
	for g.in_play {
		clear_charms(&g)
		step(&g)
	}
	testing.expect(t, g.crashed)
	testing.expect_value(t, g.tail[0], i8(COLUMNS - 1)) // the right wall
}

@(test)
test_block_crashes :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	place_next(&g, .Block, g.tail[0] + 1)
	step(&g)
	testing.expect(t, !g.in_play)
	testing.expect(t, g.crashed)
}

@(test)
test_block_beside_head_is_safe :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	place_next(&g, .Block, g.tail[0] + 2)
	step(&g)
	testing.expect(t, g.in_play)
}

@(test)
test_turn_scores_triangular_run :: proc(t: ^testing.T) {
	g := started()
	for _ in 0 ..< 4 {
		clear_charms(&g)
		step(&g)
	}
	testing.expect_value(t, g.run, 4)
	turn(&g, -1)
	testing.expect_value(t, g.score, 10) // 4 * 5 / 2
	testing.expect_value(t, g.run, 0)
	testing.expect_value(t, g.direction, i8(-1))
	testing.expect_value(t, g.high, 10)
	testing.expect(t, g.dirty)
}

@(test)
test_turning_the_same_way_does_nothing :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	step(&g)
	turn(&g, 1)
	testing.expect_value(t, g.score, 0)
	testing.expect_value(t, g.run, 1)
	testing.expect_value(t, g.sfx_count, 0)
}

@(test)
test_turn_ignored_when_not_in_play :: proc(t: ^testing.T) {
	g := new_game(3)
	turn(&g, -1)
	testing.expect_value(t, g.direction, 1)
}

@(test)
test_coin_adds_money :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	place_next(&g, .Coin, g.tail[0] + 1)
	step(&g)
	testing.expect(t, g.in_play)
	testing.expect_value(t, g.money, 1)
	s, ok := take_sfx(&g)
	testing.expect(t, ok)
	testing.expect_value(t, s, Sound.Coin)
}

@(test)
test_bank_deposits_money :: proc(t: ^testing.T) {
	g := started()
	g.money = 7
	clear_charms(&g)
	place_next(&g, .Bank, g.tail[0] + 1)
	step(&g)
	testing.expect_value(t, g.money, 0)
	testing.expect_value(t, g.bank, 7)
	testing.expect(t, g.dirty)
}

@(test)
test_crash_loses_money :: proc(t: ^testing.T) {
	g := started()
	g.money = 4
	clear_charms(&g)
	place_next(&g, .Block, g.tail[0] + 1)
	step(&g)
	testing.expect_value(t, g.money, 0)
	testing.expect_value(t, g.lost, 4)
	testing.expect_value(t, g.bank, 0)
}

@(test)
test_restart_keeps_persistent_values :: proc(t: ^testing.T) {
	g := started()
	g.high, g.bank = 99, 12
	g.in_play = false
	command(&g, .Start)
	testing.expect_value(t, g.high, 99)
	testing.expect_value(t, g.bank, 12)
	testing.expect_value(t, g.score, 0)
}

@(test)
test_tick_uses_step_time :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	tick(&g, STEP_TIME * 0.5)
	testing.expect_value(t, g.run, 0)
	tick(&g, STEP_TIME * 0.6)
	testing.expect_value(t, g.run, 1)
}

@(test)
test_mute_silences_and_flags_save :: proc(t: ^testing.T) {
	g := started()
	command(&g, .Mute)
	testing.expect(t, g.muted)
	testing.expect(t, g.dirty)
	turn(&g, -1)
	testing.expect_value(t, g.sfx_count, 0)
}

@(test)
test_sfx_queue_is_fifo_and_bounded :: proc(t: ^testing.T) {
	g := new_game(1)
	play_sound(&g, .Coin)
	play_sound(&g, .Bank)
	a, _ := take_sfx(&g)
	b, _ := take_sfx(&g)
	testing.expect_value(t, a, Sound.Coin)
	testing.expect_value(t, b, Sound.Bank)
	_, ok := take_sfx(&g)
	testing.expect(t, !ok)
	for _ in 0 ..< SFX_CAP + 5 {
		play_sound(&g, .Turn)
	}
	testing.expect_value(t, g.sfx_count, SFX_CAP)
}

@(test)
test_charm_odds_follow_weights :: proc(t: ^testing.T) {
	g := new_game(42)
	counts: [Charm]int
	for _ in 0 ..< 20000 {
		counts[pick_charm(&g)] += 1
	}
	testing.expect_value(t, counts[.None], 0)
	testing.expect(t, counts[.Block] > 17000, "blocks are about 90%")
	testing.expect(t, counts[.Coin] > 1400 && counts[.Coin] < 2200, "coins are about 9%")
	testing.expect(t, counts[.Bank] > 80 && counts[.Bank] < 320, "banks are about 1%")
}

@(test)
test_new_rows_stay_between_the_walls :: proc(t: ^testing.T) {
	g := started(9)
	for _ in 0 ..< 5000 {
		g.in_play = true
		g.tail[0] = COLUMNS / 2
		step(&g)
		testing.expect(t, g.columns[ROWS - 1] >= SPAWN_MIN && g.columns[ROWS - 1] <= SPAWN_MAX)
		testing.expect(t, g.columns[ROWS - 1] > 1 && g.columns[ROWS - 1] < COLUMNS - 2, "never beside a wall")
	}
}

@(test)
test_soak_random_play_keeps_invariants :: proc(t: ^testing.T) {
	g := new_game(77)
	for i in 0 ..< 20000 {
		if !g.in_play {
			command(&g, .Start)
		}
		if next_u32(&g) % 7 == 0 {
			command(&g, next_u32(&g) % 2 == 0 ? .Left : .Right)
		}
		tick(&g, STEP_TIME)
		if g.in_play {
			for c in g.tail {
				testing.expect(t, c > 0 && c < COLUMNS - 1)
			}
		}
		testing.expect(t, g.score >= 0 && g.money >= 0 && g.bank >= 0)
		for g.sfx_count > 0 {
			take_sfx(&g)
		}
	}
	testing.expect(t, g.high > 0)
}

// ---- renderer ----

@(test)
test_render_draws_head_tail_walls_and_charms :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	g.charms[10], g.columns[10] = .Block, 5
	g.charms[11], g.columns[11] = .Coin, 7
	g.charms[12], g.columns[12] = .Bank, 9
	f := new(Frame)
	defer free(f)
	render(&g, f)
	px :: proc(f: ^Frame, col, row: int) -> u32 {
		return f[(row * CELL + 3) * WIDTH + col * CELL + 3]
	}
	testing.expect_value(t, px(f, 0, 15), u32(BLUE))
	testing.expect_value(t, px(f, COLUMNS - 1, 15), u32(BLUE))
	testing.expect_value(t, px(f, 5, 10), u32(WHITE))
	testing.expect_value(t, px(f, 7, 11), u32(YELLOW)) // the coin's bright middle
	testing.expect_value(t, f[(12 * CELL + 7) * WIDTH + 9 * CELL + 7], u32(BRIGHT_GREEN)) // the bank's corner, clear of the $
	testing.expect_value(t, px(f, int(g.tail[0]), HEAD_ROW), u32(RED))
	testing.expect_value(t, px(f, int(g.tail[1]), HEAD_ROW - 1), u32(YELLOW))
}

@(test)
test_menu_text_fits_in_the_panel :: proc(t: ^testing.T) {
	lines := MENU_LINES
	for line in lines {
		testing.expectf(t, text_width(line, 1) <= PANEL_W - 8, "%q is %d wide", line, text_width(line, 1))
	}
	testing.expect(t, text_width("JETLAG", 4) <= PANEL_W - 8)
	testing.expect(t, text_width("COINS ARE LOST IF YOU CRASH", 1) > 0)
}

@(test)
test_menu_shows_only_when_not_in_play :: proc(t: ^testing.T) {
	g := new_game(1)
	f := new(Frame)
	defer free(f)
	render(&g, f)
	menu_pixel := f[(PANEL_Y) * WIDTH + WIDTH / 2]
	testing.expect_value(t, menu_pixel, u32(GRAY)) // the panel's top border
	command(&g, .Start)
	render(&g, f)
	testing.expect(t, f[(PANEL_Y) * WIDTH + WIDTH / 2] != u32(GRAY))
}

@(test)
test_itoa :: proc(t: ^testing.T) {
	buf: [40]u8
	testing.expect_value(t, itoa(buf[:], "", 0), "0")
	testing.expect_value(t, itoa(buf[:], "$", 1234567), "$1234567")
	testing.expect_value(t, itoa(buf[:], "HI ", -5), "HI 0")
}

@(test)
test_text_draws_pixels :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	draw_text(f, 10, 10, "A", WHITE, 1)
	lit := 0
	for p in f {
		if p == u32(WHITE) {
			lit += 1
		}
	}
	testing.expect(t, lit > 8)
}

// ---- screenshots (run with -define:JETLAG_SHOTS=true; see tools/shots.sh) ----

import "core:os"

JETLAG_SHOTS :: #config(JETLAG_SHOTS, false)

write_ppm :: proc(f: ^Frame, path: string) {
	data := make([]u8, WIDTH * HEIGHT * 3 + 20)
	defer delete(data)
	header := "P6\n320 240\n255\n"
	n := copy(data, header)
	for p in f {
		data[n] = u8(p)
		data[n + 1] = u8(p >> 8)
		data[n + 2] = u8(p >> 16)
		n += 3
	}
	_ = os.write_entire_file(path, data[:n])
}

// bot_turn dodges: turn when the cell the head is about to enter, or the one after, holds a block or a wall.
bot_turn :: proc(g: ^Game) {
	ahead := g.tail[0] + g.direction * 2
	hit := ahead <= 1 || ahead >= COLUMNS - 2
	for r in HEAD_ROW + 1 ..= HEAD_ROW + 2 {
		if g.charms[r] == .Block && (g.columns[r] == g.tail[0] + g.direction || g.columns[r] == ahead) {
			hit = true
		}
	}
	if hit {
		turn(g, -g.direction)
	}
}

@(test)
test_bot_survives_a_while :: proc(t: ^testing.T) {
	g := started(11)
	steps := 0
	for g.in_play && steps < 3000 {
		bot_turn(&g)
		step(&g)
		steps += 1
	}
	testing.expect(t, steps > 100, "the dodge bot should last a while")
	when JETLAG_SHOTS {
		f := new(Frame)
		defer free(f)
		g2 := new_game(5)
		render(&g2, f)
		write_ppm(f, "build/shots/title.ppm")
		command(&g2, .Start)
		for _ in 0 ..< 70 {
			bot_turn(&g2)
			step(&g2)
		}
		g2.money = 3
		render(&g2, f)
		write_ppm(f, "build/shots/play.ppm")
		g2.high = 412
		g2.bank = 27
		g2.score = 132
		g2.lost = 3
		crash(&g2)
		render(&g2, f)
		write_ppm(f, "build/shots/crashed.ppm")
		g2.bombs = 1
		command(&g2, .Shop)
		render(&g2, f)
		write_ppm(f, "build/shots/shop.ppm")
	}
}

@(test)
test_crash_queues_the_score_once :: proc(t: ^testing.T) {
	g := started()
	g.score = 40
	crash(&g)
	s, ok := take_submit(&g)
	testing.expect(t, ok)
	testing.expect_value(t, s, 40)
	_, again := take_submit(&g)
	testing.expect(t, !again)
}

@(test)
test_zero_score_is_not_submitted :: proc(t: ^testing.T) {
	g := started()
	crash(&g)
	_, ok := take_submit(&g)
	testing.expect(t, !ok)
}

@(test)
test_board_screen_toggles_only_out_of_play :: proc(t: ^testing.T) {
	g := new_game(3)
	command(&g, .Board)
	testing.expect(t, g.show_board)
	command(&g, .Start) // flying hides it
	testing.expect(t, !g.show_board && g.in_play)
	command(&g, .Board)
	testing.expect(t, !g.show_board)
}

@(test)
test_board_rows_are_capped_and_names_cleaned :: proc(t: ^testing.T) {
	g := new_game(3)
	for i in 0 ..< BOARD_ROWS + 3 {
		board_add(&g, transmute([]u8)string("A very long player name\xff"), i)
	}
	testing.expect_value(t, g.board_count, BOARD_ROWS)
	testing.expect_value(t, g.board[0].name_len, NAME_LEN)
	board_begin(&g)
	board_add(&g, {'o', 0xe9, 'k'}, 9)
	testing.expect_value(t, g.board[0].name[1], u8('?'))
}

@(test)
test_bomb_clears_every_block_and_is_spent :: proc(t: ^testing.T) {
	g := started()
	g.bombs = 2
	g.charms[3], g.charms[10], g.charms[ROWS - 1] = .Block, .Block, .Block
	g.charms[5] = .Coin
	command(&g, .Bomb)
	for r in 0 ..< ROWS {
		testing.expect(t, g.charms[r] != .Block)
	}
	testing.expect_value(t, g.charms[5], Charm.Coin)
	testing.expect_value(t, g.bombs, 1)
	testing.expect(t, g.dirty)
	testing.expect_value(t, g.sfx_count, 1)
}

@(test)
test_bomb_kept_with_nothing_to_clear_or_none_owned :: proc(t: ^testing.T) {
	g := started()
	clear_charms(&g)
	g.bombs = 1
	command(&g, .Bomb)
	testing.expect_value(t, g.bombs, 1)
	g.bombs = 0
	g.charms[4] = .Block
	command(&g, .Bomb)
	testing.expect_value(t, g.charms[4], Charm.Block)
}

@(test)
test_bomb_ignored_between_runs :: proc(t: ^testing.T) {
	g := new_game(1)
	g.bombs = 1
	g.charms[4] = .Block
	command(&g, .Bomb)
	testing.expect_value(t, g.bombs, 1)
}

@(test)
test_shop_buys_a_bomb_from_the_bank :: proc(t: ^testing.T) {
	g := new_game(1)
	g.bank = 25
	command(&g, .Buy) // not in the shop yet
	testing.expect_value(t, g.bombs, 0)
	command(&g, .Shop)
	testing.expect(t, g.show_shop)
	command(&g, .Buy)
	command(&g, .Buy)
	testing.expect_value(t, g.bombs, 2)
	testing.expect_value(t, g.bank, 5)
	command(&g, .Buy) // cannot afford
	testing.expect_value(t, g.bombs, 2)
	g.bank = 100
	command(&g, .Buy)
	command(&g, .Buy) // carrying the most
	testing.expect_value(t, g.bombs, MAX_BOMBS)
	testing.expect_value(t, g.bank, 90)
}

@(test)
test_bombs_survive_a_crash_and_the_shop_closes_on_start :: proc(t: ^testing.T) {
	g := new_game(1)
	g.bombs = 2
	command(&g, .Shop)
	command(&g, .Start)
	testing.expect(t, g.in_play)
	testing.expect(t, !g.show_shop)
	command(&g, .Shop) // no shop mid-run
	testing.expect(t, !g.show_shop)
	crash(&g)
	testing.expect_value(t, g.bombs, 2)
}

@(test)
test_menu_text_does_not_overlap_the_footer :: proc(t: ^testing.T) {
	// the crash report with the longest rules block must end above the bank line, which sits above the footer
	testing.expect(t, 106 + 11 * len(MENU_LINES) <= PANEL_Y + PANEL_H - 38)
}
