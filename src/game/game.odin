// JetLag rules. No platform imports: the page (src/web) and the tests both drive this package.
//
// A jet flies down a 40 by 30 grid, leaving a six-cell tail above it, so the board scrolls up. Each tick a
// new row scrolls in from the bottom with one charm in it (a block, a coin or a bank) and the jet moves one column in its direction.
// Turning scores the triangular number of the ticks since the last turn, so long straight runs pay
// (from JetLag 2020); coins and banks come from JetLag 2023.
package game

COLUMNS :: 40
ROWS :: 30
TAIL_LENGTH :: 6
HEAD_ROW :: TAIL_LENGTH + 1 // the row the jet's head is on (0-based; row 0 is the HUD); the tail trails above it
// Charms never spawn against a wall: the wall is column 0 and COLUMNS-1, and one clear column is kept beside it.
SPAWN_MIN :: 2
SPAWN_MAX :: COLUMNS - 3
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
	Bomb,
}

Command :: enum i32 {
	Left,
	Right,
	Start,
	Mute,
	Board,
	Bomb, // in a run: turn every block on the screen into a coin
	Shop, // between runs: open or close the shop
	Buy, // in the shop: buy the selected item
	Up, // in the shop: move the cursor
	Down,
}

// The shop. Bombs are bought with the bank between runs and kept until used, a crash does not take them.
BOMB_PRICE :: 10
BASE_BOMBS :: 3 // what you can carry before any upgrade
MAX_BOMB_LEVEL :: 6 // upgrades: capacity tops out at BASE_BOMBS + MAX_BOMB_LEVEL
CAPACITY_BASE_PRICE :: 25 // the first upgrade; each one costs double the last

Shop_Item :: enum u8 {
	Bomb,
	Capacity,
}

SFX_CAP :: 8

// The online top scores (LootLocker). The page fetches them and hands them over through board_add.
BOARD_ROWS :: 10
NAME_LEN :: 16

Board_Status :: enum u8 {
	Idle, // nothing asked for yet
	Loading,
	Ready,
	Failed, // offline or the service said no; the game plays on regardless
}

Board_Entry :: struct {
	name:     [NAME_LEN]u8,
	name_len: int,
	score:    int,
}

Game :: struct {
	charms:    [ROWS]Charm,
	columns:   [ROWS]i8, // column of each row's charm
	tail:      [TAIL_LENGTH]i8, // tail[0] is the head
	direction: i8, // -1 left, 1 right
	timer:     f32,
	run:       int, // ticks since the last turn
	score:     int,
	money:     int, // this run; a crash banks half of it (rounded down) and loses the rest
	lost:      int, // the money the last crash cost
	kept:      int, // the money the last crash banked
	in_play:   bool,
	crashed:   bool, // a run has ended since the page loaded (shows the crash screen)
	high:      int, // persisted
	bank:      int, // persisted
	bombs:     int, // persisted, at most max_bombs
	bomb_level: int, // persisted, capacity upgrades bought
	muted:     bool, // persisted
	dirty:     bool, // high, bank, bombs or muted changed; the page saves and clears it
	sfx:       [SFX_CAP]Sound,
	sfx_count: int,
	rng:       u64,
	// online scores (not persisted here; the page owns the account)
	show_board:      bool, // the top-scores screen is up instead of the rules
	show_shop:       bool, // the shop is up instead of the rules
	shop_sel:        Shop_Item, // the shop's cursor
	board_status:    Board_Status,
	board:           [BOARD_ROWS]Board_Entry,
	board_count:     int,
	player:          Board_Entry, // this player's name (score unused)
	submit:          int, // a finished run's score the page should send; 0 when none is waiting
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
	g.kept = 0
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
	// The modulo is done in u32: on js_wasm32 int is 32 bits, so int(u32) can go negative and spawn outside [lo, hi].
	return lo + int(next_u32(g) % u32(hi - lo + 1))
}

pick_charm :: proc(g: ^Game) -> Charm {
	weights := CHARM_WEIGHTS
	total := 0
	for w in weights {
		total += w
	}
	roll := int(next_u32(g) % u32(total))
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
			g.show_board = false
			g.show_shop = false
		}
	case .Mute:
		g.muted = !g.muted
		g.dirty = true
		if g.muted {
			g.sfx_count = 0
		}
	case .Board:
		if !g.in_play {
			g.show_board = !g.show_board
			g.show_shop = false
		}
	case .Bomb:
		use_bomb(g)
	case .Shop:
		if !g.in_play {
			g.show_shop = !g.show_shop
			g.show_board = false
		}
	case .Buy:
		buy(g)
	case .Up:
		if g.show_shop && !g.in_play {
			g.shop_sel = .Bomb
		}
	case .Down:
		if g.show_shop && !g.in_play {
			g.shop_sel = .Capacity
		}
	}
}

// use_bomb spends a bomb to turn every block on the screen into a coin where it stands. With no blocks the bomb is kept.
use_bomb :: proc(g: ^Game) {
	if !g.in_play || g.bombs <= 0 {
		return
	}
	converted := false
	for r in 0 ..< ROWS {
		if g.charms[r] == .Block {
			g.charms[r] = .Coin
			converted = true
		}
	}
	if !converted {
		return
	}
	g.bombs -= 1
	g.dirty = true
	play_sound(g, .Bomb)
}

// max_bombs is how many bombs you can carry.
max_bombs :: proc(g: ^Game) -> int {
	return BASE_BOMBS + g.bomb_level
}

// capacity_price is the cost of the next capacity upgrade; ok is false once they are all bought.
capacity_price :: proc(g: ^Game) -> (price: int, ok: bool) {
	if g.bomb_level >= MAX_BOMB_LEVEL {
		return 0, false
	}
	return CAPACITY_BASE_PRICE << uint(g.bomb_level), true
}

// buy trades bank money for the item under the shop's cursor, in the shop only.
buy :: proc(g: ^Game) {
	if g.in_play || !g.show_shop {
		return
	}
	price: int
	switch g.shop_sel {
	case .Bomb:
		price = BOMB_PRICE
		if g.bombs >= max_bombs(g) || g.bank < price {
			return
		}
		g.bombs += 1
	case .Capacity:
		ok: bool
		price, ok = capacity_price(g)
		if !ok || g.bank < price {
			return
		}
		g.bomb_level += 1
	}
	g.bank -= price
	g.dirty = true
	play_sound(g, .Bank)
}

// set_entry copies text into an entry's name, keeping printable ASCII and cutting it to NAME_LEN.
set_entry :: proc(e: ^Board_Entry, name: []u8, score: int) {
	e.name_len = 0
	for c in name {
		if e.name_len >= NAME_LEN {
			break
		}
		e.name[e.name_len] = c >= 32 && c <= 126 ? c : '?'
		e.name_len += 1
	}
	e.score = score
}

board_begin :: proc(g: ^Game) {
	g.board_count = 0
}

board_add :: proc(g: ^Game, name: []u8, score: int) {
	if g.board_count >= BOARD_ROWS {
		return
	}
	set_entry(&g.board[g.board_count], name, score)
	g.board_count += 1
}

// take_submit pops the score waiting to go online.
take_submit :: proc(g: ^Game) -> (score: int, ok: bool) {
	if g.submit <= 0 {
		return
	}
	score, g.submit = g.submit, 0
	return score, true
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
	for r in 0 ..< ROWS - 1 {
		g.charms[r] = g.charms[r + 1]
		g.columns[r] = g.columns[r + 1]
	}
	g.charms[ROWS - 1] = pick_charm(g)
	g.columns[ROWS - 1] = i8(range_i(g, SPAWN_MIN, SPAWN_MAX))

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
	g.kept = g.money / 2
	g.lost = g.money - g.kept
	g.money = 0
	if g.kept > 0 {
		g.bank += g.kept
		g.dirty = true
	}
	g.show_board = false
	g.submit = g.score
	play_sound(g, .Death)
}
