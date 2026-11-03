// Software renderer: draws the whole 320 by 240 picture into a frame of RGBA pixels (bytes R, G, B, A).
package game

CELL :: 8
WIDTH :: COLUMNS * CELL
HEIGHT :: ROWS * CELL

Frame :: [WIDTH * HEIGHT]u32

rgb :: proc(r, g, b: u32) -> u32 {
	return 0xff000000 | b << 16 | g << 8 | r
}

// The 16 colours of the original's ROM font sheet are the CGA palette.
BLACK :: 0xff000000
BLUE :: 0xffaa0000 // (0, 0, 170)
RED :: 0xff0000aa // (170, 0, 0)
GREEN :: 0xff00aa00
YELLOW :: 0xff55ffff // (255, 255, 85)
GOLD :: 0xff00aaff // (255, 170, 0)
WHITE :: 0xffffffff
GRAY :: 0xffaaaaaa
BRIGHT_GREEN :: 0xff55ff55
DARK_GREEN :: 0xff005500
DIM :: 0xe0000000 // unused alpha marker; panels are opaque

fill :: proc(f: ^Frame, x, y, w, h: int, color: u32) {
	for yy in max(y, 0) ..< min(y + h, HEIGHT) {
		for xx in max(x, 0) ..< min(x + w, WIDTH) {
			f[yy * WIDTH + xx] = color
		}
	}
}

glyph_index :: proc(c: u8) -> int {
	if c < 32 || c > 126 {
		return int('?') - 32
	}
	return int(c) - 32
}

draw_glyph :: proc(f: ^Frame, x, y: int, c: u8, color: u32, scale: int) {
	rows := FONT_GLYPHS[glyph_index(c)]
	for row in 0 ..< FONT_ROWS {
		bits := rows[row]
		for col in 0 ..< 8 {
			if bits & (0x80 >> uint(col)) != 0 {
				fill(f, x + col * scale, y + row * scale, scale, scale, color)
			}
		}
	}
}

text_width :: proc(text: string, scale: int) -> int {
	w := 0
	for i in 0 ..< len(text) {
		w += int(FONT_ADVANCE[glyph_index(text[i])]) + 1
	}
	return max(w - 1, 0) * scale
}

draw_text :: proc(f: ^Frame, x, y: int, text: string, color: u32, scale: int) {
	cx := x
	for i in 0 ..< len(text) {
		c := text[i]
		draw_glyph(f, cx, y, c, color, scale)
		cx += (int(FONT_ADVANCE[glyph_index(c)]) + 1) * scale
	}
}

draw_text_centered :: proc(f: ^Frame, y: int, text: string, color: u32, scale: int) {
	draw_text(f, (WIDTH - text_width(text, scale)) / 2, y, text, color, scale)
}

draw_text_right :: proc(f: ^Frame, right, y: int, text: string, color: u32, scale: int) {
	draw_text(f, right - text_width(text, scale), y, text, color, scale)
}

// itoa writes n into buf and returns the text. buf must hold the prefix plus 20 digits.
itoa :: proc(buf: []u8, prefix: string, n: int) -> string {
	pos := 0
	for i in 0 ..< len(prefix) {
		buf[pos] = prefix[i]
		pos += 1
	}
	digits: [20]u8
	count := 0
	v := max(n, 0)
	for {
		digits[count] = u8('0' + v % 10)
		count += 1
		v /= 10
		if v == 0 {
			break
		}
	}
	for count > 0 {
		count -= 1
		buf[pos] = digits[count]
		pos += 1
	}
	return string(buf[:pos])
}

digit_count :: proc(n: int) -> int {
	count := 1
	for v := n / 10; v > 0; v /= 10 {
		count += 1
	}
	return count
}

draw_cell :: proc(f: ^Frame, column, row: int, color: u32) {
	fill(f, column * CELL, row * CELL, CELL, CELL, color)
}

draw_coin :: proc(f: ^Frame, column, row: int) {
	x, y := column * CELL, row * CELL
	fill(f, x + 2, y + 1, 4, 6, GOLD)
	fill(f, x + 1, y + 2, 6, 4, GOLD)
	fill(f, x + 3, y + 2, 2, 4, YELLOW)
}

draw_bank :: proc(f: ^Frame, column, row: int) {
	draw_cell(f, column, row, BRIGHT_GREEN)
	draw_glyph(f, column * CELL + 1, row * CELL - 1, '$', DARK_GREEN, 1)
}

render :: proc(g: ^Game, f: ^Frame) {
	// playfield
	fill(f, 0, 0, WIDTH, HEIGHT, BLACK)
	for row in 0 ..< ROWS {
		draw_cell(f, 0, row, BLUE)
		draw_cell(f, COLUMNS - 1, row, BLUE)
		col := int(g.columns[row])
		switch g.charms[row] {
		case .None:
		case .Block:
			draw_cell(f, col, row, WHITE)
		case .Coin:
			draw_coin(f, col, row)
		case .Bank:
			draw_bank(f, col, row)
		}
	}
	for i := TAIL_LENGTH - 1; i >= 0; i -= 1 {
		draw_cell(f, int(g.tail[i]), HEAD_ROW - i, i == 0 ? RED : YELLOW)
	}

	// HUD in the top row
	buf: [40]u8
	fill(f, 0, 0, WIDTH, CELL, BLACK)
	draw_text(f, 12, -1, itoa(buf[:], "", g.score), GRAY, 1)
	draw_text_centered(f, -1, itoa(buf[:], "$", g.money), GOLD, 1)
	draw_text_right(f, WIDTH - 12, -1, itoa(buf[:], "HI ", g.high), GRAY, 1)
	if g.bombs > 0 {
		draw_text(f, 76, -1, itoa(buf[:], "BOMBS ", g.bombs), RED, 1)
	}

	if g.in_play {
		if bomb_button_shown(g) {
			fill(f, BOMB_BTN_X, BOMB_BTN_Y, BOMB_BTN_W, BOMB_BTN_H, RED)
			fill(f, BOMB_BTN_X + 1, BOMB_BTN_Y + 1, BOMB_BTN_W - 2, BOMB_BTN_H - 2, BLACK)
			draw_text_centered_in(f, BOMB_BTN_X, BOMB_BTN_W, BOMB_BTN_Y + 3, itoa(buf[:], "BOMB ", g.bombs), WHITE, 1)
		}
		return
	}
	draw_menu(g, f)
}

draw_board :: proc(g: ^Game, f: ^Frame) {
	buf: [40]u8
	draw_text_centered(f, 30, "TOP SCORES", YELLOW, 2)
	y := 54
	switch g.board_status {
	case .Idle, .Loading:
		draw_text_centered(f, y + 40, "LOADING...", GRAY, 1)
	case .Failed:
		draw_text_centered(f, y + 40, "SCORES ARE OFFLINE", GRAY, 1)
	case .Ready:
		if g.board_count == 0 {
			draw_text_centered(f, y + 40, "NO SCORES YET", GRAY, 1)
		}
		for i in 0 ..< g.board_count {
			e := g.board[i]
			mine := e.name_len > 0 && e.name_len == g.player.name_len && e.name == g.player.name
			color: u32 = mine ? WHITE : GRAY
			draw_text(f, PANEL_X + 40, y, itoa(buf[:], "", i + 1), color, 1)
			draw_text(f, PANEL_X + 64, y, string(e.name[:e.name_len]), color, 1)
			draw_text_right(f, WIDTH - PANEL_X - 40, y, itoa(buf[:], "", e.score), color, 1)
			y += 11
		}
	}
	if g.player.name_len > 0 {
		draw_text_centered(f, PANEL_Y + PANEL_H - 28, string(g.player.name[:g.player.name_len]), GOLD, 1)
	}
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 12, "Z OR X: BACK", GRAY, 1)
	draw_back(f)
}

MENU_LABELS :: [Menu_Item]string{
	.Start  = "START GAME",
	.Shop   = "SHOP",
	.Scores = "HIGH SCORES",
	.Help   = "HOW TO PLAY",
	.Sound  = "SOUND",
}

HELP_LINES :: [?]string{
	"LEFT / RIGHT, A / D OR TAP A SIDE TO TURN",
	"A LONG RUN BEFORE A TURN SCORES MORE",
	"Z OR SPACE DROPS A BOMB: BLOCKS TO COINS",
	"A CRASH KEEPS HALF YOUR COINS",
	"HIT A GREEN $ TO BANK THEM",
}

// draw_back is the BACK button of the screens a menu opens (X or Esc does the same).
draw_back :: proc(f: ^Frame) {
	fill(f, BACK_X, BACK_Y, BACK_W, BACK_H, GRAY)
	fill(f, BACK_X + 1, BACK_Y + 1, BACK_W - 2, BACK_H - 2, BLACK)
	draw_text_centered_in(f, BACK_X, BACK_W, BACK_Y + 3, "BACK", WHITE, 1)
}

draw_text_centered_in :: proc(f: ^Frame, x, w, y: int, text: string, color: u32, scale: int) {
	draw_text(f, x + (w - text_width(text, scale)) / 2, y, text, color, scale)
}

draw_help :: proc(f: ^Frame) {
	draw_text_centered(f, 30, "HOW TO PLAY", YELLOW, 2)
	lines := HELP_LINES
	y := 62
	for line in lines {
		draw_text_centered(f, y, line, GRAY, 1)
		y += 14
	}
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 12, "Z OR X: BACK", GRAY, 1)
	draw_back(f)
}

draw_shop :: proc(g: ^Game, f: ^Frame) {
	buf, buf2: [40]u8
	draw_text_centered(f, 30, "SHOP", YELLOW, 2)
	draw_text_centered(f, 52, itoa(buf[:], "BANK $", g.bank), GOLD, 1)
	draw_text_centered(f, 70, "Z OR SPACE IN A RUN TURNS BLOCKS TO COINS", GRAY, 1)
	draw_text_centered(f, 82, "(OR THE BOMB BUTTON ON A PHONE)", GRAY, 1)

	ys := SHOP_ROW_Y
	draw_shop_row(f, ys[.Bomb], g.shop_sel == .Bomb, itoa(buf[:], "BOMB  $", BOMB_PRICE), itoa(buf2[:], "HAVE ", g.bombs))
	if price, ok := capacity_price(g); ok {
		draw_shop_row(f, ys[.Capacity], g.shop_sel == .Capacity, itoa(buf[:], "CARRY MORE  $", price), itoa(buf2[:], "NOW ", max_bombs(g)))
	} else {
		draw_shop_row(f, ys[.Capacity], g.shop_sel == .Capacity, "CARRY MORE  MAXED", itoa(buf2[:], "NOW ", max_bombs(g)))
	}

	status: string
	switch g.shop_sel {
	case .Bomb:
		switch {
		case g.bombs >= max_bombs(g):
			status = "YOU ARE CARRYING THE MOST YOU CAN"
		case g.bank < BOMB_PRICE:
			status = "NOT ENOUGH IN THE BANK"
		}
	case .Capacity:
		price, ok := capacity_price(g)
		switch {
		case !ok:
			status = "YOU CANNOT CARRY ANY MORE"
		case g.bank < price:
			status = "NOT ENOUGH IN THE BANK"
		}
	}
	if status != "" {
		draw_text_centered(f, 148, status, RED, 1)
	} else {
		draw_text_centered(f, 148, "Z OR TAP A ROW: BUY", WHITE, 1)
	}
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 12, "UP / DOWN: PICK   X: BACK", GRAY, 1)
	draw_back(f)
}

draw_shop_row :: proc(f: ^Frame, y: int, selected: bool, left, right: string) {
	color: u32 = selected ? WHITE : GRAY
	if selected {
		draw_text(f, PANEL_X + 40, y, ">", YELLOW, 1)
	}
	draw_text(f, PANEL_X + 52, y, left, color, 1)
	draw_text_right(f, WIDTH - PANEL_X - 40, y, right, color, 1)
}

draw_menu :: proc(g: ^Game, f: ^Frame) {
	buf: [40]u8
	fill(f, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, BLACK)
	fill(f, PANEL_X, PANEL_Y, PANEL_W, 1, GRAY)
	fill(f, PANEL_X, PANEL_Y + PANEL_H - 1, PANEL_W, 1, GRAY)
	switch g.screen {
	case .Scores:
		draw_board(g, f)
		return
	case .Shop:
		draw_shop(g, f)
		return
	case .Help:
		draw_help(f)
		return
	case .Menu:
	}
	// Rows from the top of the panel down: logo, crash report (or tagline), the menu, the bank, then the hint.
	draw_text_centered(f, 30, "JETLAG", YELLOW, 4)
	if g.crashed {
		draw_text_centered(f, 66, "CRASHED", RED, 2)
		draw_text_centered(f, 83, itoa(buf[:], "SCORE ", g.score), WHITE, 1)
		if g.kept > 0 || g.lost > 0 {
			buf2: [40]u8
			text := itoa(buf[:], "KEPT $", g.kept)
			w := text_width(text, 1) + 16 + text_width(itoa(buf2[:], "LOST $", g.lost), 1)
			x := (WIDTH - w) / 2
			draw_text(f, x, 94, text, GOLD, 1)
			draw_text(f, x + text_width(text, 1) + 16, 94, string(buf2[:len("LOST $") + digit_count(g.lost)]), RED, 1)
		}
	} else {
		draw_text_centered(f, 72, "KEEP THE TAIL OFF THE BLOCKS", GRAY, 1)
	}
	labels := MENU_LABELS
	for item in Menu_Item {
		y := MENU_TOP + int(item) * MENU_ROW
		selected := item == g.menu_sel
		label := labels[item]
		if item == .Sound {
			label = g.muted ? "SOUND: OFF" : "SOUND: ON"
		}
		if selected {
			draw_text(f, WIDTH / 2 - 60, y, ">", YELLOW, 1)
		}
		draw_text_centered(f, y, label, selected ? WHITE : GRAY, 1)
	}
	draw_text_centered(f, PANEL_Y + PANEL_H - 28, itoa(buf[:], "BANK $", g.bank), GOLD, 1)
	draw_text_centered(f, PANEL_Y + PANEL_H - 14, "UP / DOWN: PICK   Z: OK", GRAY, 1)
}
