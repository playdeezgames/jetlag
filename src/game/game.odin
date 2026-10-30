// JetLag rules. No platform imports: the page (src/web) and the tests both drive this package.
//
// A jet flies up a 40 by 30 grid, leaving a six-cell tail. Each tick a new row scrolls in from the top
// with one charm in it (a block, a coin or a bank) and the jet moves one column in its direction.
// Turning scores the triangular number of the ticks since the last turn, so long straight runs pay
// (from JetLag 2020); coins and banks come from JetLag 2023.
package game

COLUMNS :: 40
ROWS :: 30
TAIL_LENGTH :: 6
HEAD_ROW :: ROWS - TAIL_LENGTH // the row the jet's head is on (0-based; the top row is 0)
STEP_TIME :: 0.1 // seconds per tick

Charm :: enum u8 {
	None,
	Block, // crash
	Coin, // +$1 this run
	Bank, // deposits this run's money into the bank
}

// Weights for the charm dropped into each new row (JetLag 2023: 90 blocks, 9 coins, 1 bank).
CHARM_WEIGHTS :: [Charm]int{.None = 0, .Block = 90, .Coin = 9, .Bank = 1}

// The order must match the page's SOUND_FILES.
Sound :: enum u8 {
	Turn,
	Death,
	Coin,
	Bank,
}

Command :: enum i32 {
	Left,
	Right,
	Start,
	Mute,
}

SFX_CAP :: 8

Game :: struct {
	charms:    [ROWS]Charm,
	columns:   [ROWS]i8, // column of each row's charm
	tail:      [TAIL_LENGTH]i8, // tail[0] is the head
	direction: i8, // -1 left, 1 right
	timer:     f32,
	run:       int, // ticks since the last turn
	score:     int,
	money:     int, // this run, lost on a crash unless banked
	lost:      int, // the money the last crash cost
	in_play:   bool,
	crashed:   bool, // a run has ended since the page loaded (shows the crash screen)
	high:      int, // persisted
	bank:      int, // persisted
	muted:     bool, // persisted
	dirty:     bool, // high, bank or muted changed; the page saves and clears it
	sfx:       [SFX_CAP]Sound,
	sfx_count: int,
	rng:       u64,
}

new_game :: proc(seed: u64) -> Game {
	g: Game
	g.rng = seed * 0x9E3779B97F4A7C15 + 0x1234567
	if g.rng == 0 {
		g.rng = 1
	}
	reset(&g)
	return g
}

// reset starts a fresh run's board; persisted values stay.
reset :: proc(g: ^Game) {
	g.charms = {}
	g.columns = {}
	for i in 0 ..< TAIL_LENGTH {
		g.tail[i] = COLUMNS / 2 - 1
	}
	g.direction = 1
	g.timer = 0
	g.run = 0
	g.score = 0
	g.money = 0
	g.lost = 0
}

next_u32 :: proc(g: ^Game) -> u32 {
	// xorshift64*
	x := g.rng
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	g.rng = x
	return u32((x * 0x2545F4914F6CDD1D) >> 32)
}

// range_i returns a number in [lo, hi].
range_i :: proc(g: ^Game, lo, hi: int) -> int {
	return lo + int(next_u32(g)) % (hi - lo + 1)
}

pick_charm :: proc(g: ^Game) -> Charm {
	weights := CHARM_WEIGHTS
	total := 0
	for w in weights {
		total += w
	}
	roll := int(next_u32(g)) % total
	for w, c in weights {
		if roll < w {
			return c
		}
		roll -= w
	}
	return .Block
}

play_sound :: proc(g: ^Game, s: Sound) {
	if g.muted || g.sfx_count >= SFX_CAP {
		return
	}
	g.sfx[g.sfx_count] = s
	g.sfx_count += 1
}

// take_sfx pops the oldest queued sound.
take_sfx :: proc(g: ^Game) -> (s: Sound, ok: bool) {
	if g.sfx_count == 0 {
		return
	}
	s = g.sfx[0]
	for i in 1 ..< g.sfx_count {
		g.sfx[i - 1] = g.sfx[i]
	}
	g.sfx_count -= 1
	return s, true
}

command :: proc(g: ^Game, c: Command) {
	switch c {
	case .Left:
		turn(g, -1)
	case .Right:
		turn(g, 1)
	case .Start:
		if !g.in_play {
			reset(g)
			g.in_play = true
		}
	case .Mute:
		g.muted = !g.muted
		g.dirty = true
		if g.muted {
			g.sfx_count = 0
		}
	}
}

// turn changes direction, scoring the run so far. Pressing the way you already go does nothing.
turn :: proc(g: ^Game, dir: i8) {
	if !g.in_play || dir == g.direction {
		return
	}
	play_sound(g, .Turn)
	g.score += g.run * (g.run + 1) / 2
	if g.score > g.high {
		g.high = g.score
		g.dirty = true
	}
	g.run = 0
	g.direction = dir
}

tick :: proc(g: ^Game, dt: f32) {
	if !g.in_play {
		return
	}
	g.timer += dt
	for g.timer >= STEP_TIME && g.in_play {
		g.timer -= STEP_TIME
		step(g)
	}
}

// step advances the world by one tick: scroll the rows, move the jet, resolve what it hit.
step :: proc(g: ^Game) {
	g.run += 1
	for r := ROWS - 1; r >= 1; r -= 1 {
		g.charms[r] = g.charms[r - 1]
		g.columns[r] = g.columns[r - 1]
	}
	g.charms[0] = pick_charm(g)
	g.columns[0] = i8(range_i(g, 1, COLUMNS - 2))

	for r := TAIL_LENGTH - 1; r >= 1; r -= 1 {
		g.tail[r] = g.tail[r - 1]
	}
	g.tail[0] += g.direction

	head := g.tail[0]
	if head <= 0 || head >= COLUMNS - 1 {
		crash(g)
		return
	}
	if g.columns[HEAD_ROW] != head {
		return
	}
	#partial switch g.charms[HEAD_ROW] {
	case .Block:
		crash(g)
	case .Coin:
		g.money += 1
		play_sound(g, .Coin)
	case .Bank:
		if g.money > 0 {
			g.bank += g.money
			g.money = 0
			g.dirty = true
		}
		play_sound(g, .Bank)
	}
}

crash :: proc(g: ^Game) {
	g.in_play = false
	g.crashed = true
	g.lost = g.money
	g.money = 0
	play_sound(g, .Death)
}
