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
		return
	}
	draw_menu(g, f)
}

PANEL_X :: 16
PANEL_Y :: 24
PANEL_W :: WIDTH - 2 * PANEL_X
PANEL_H :: 176

MENU_LINES :: [?]string{
	"Z, SPACE OR TAP TO FLY",
	"LEFT / RIGHT, A / D OR TAP A SIDE TO TURN",
	"A LONG RUN BEFORE A TURN SCORES MORE",
	"A CRASH KEEPS HALF YOUR COINS",
	"HIT A GREEN $ TO BANK THEM",
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
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 14, "B OR TAP TOP: BACK", GRAY, 1)
	draw_text_right(f, WIDTH - PANEL_X - 6, PANEL_Y + PANEL_H - 14, "Z: FLY", GRAY, 1)
}

draw_shop :: proc(g: ^Game, f: ^Frame) {
	buf: [40]u8
	draw_text_centered(f, 30, "SHOP", YELLOW, 2)
	draw_text_centered(f, 54, itoa(buf[:], "BANK $", g.bank), GOLD, 1)
	draw_text_centered(f, 84, itoa(buf[:], "BOMB  $", BOMB_PRICE), WHITE, 2)
	draw_text_centered(f, 104, itoa(buf[:], "YOU HAVE ", g.bombs), GRAY, 1)
	draw_text_centered(f, 118, "Z OR SPACE IN A RUN CLEARS ALL BLOCKS", GRAY, 1)
	draw_text_centered(f, 130, "(TWO-FINGER TAP ON A PHONE)", GRAY, 1)
	switch {
	case g.bombs >= MAX_BOMBS:
		draw_text_centered(f, 152, itoa(buf[:], "YOU CAN CARRY ", MAX_BOMBS), RED, 1)
	case g.bank < BOMB_PRICE:
		draw_text_centered(f, 152, "NOT ENOUGH IN THE BANK", RED, 1)
	case:
		draw_text_centered(f, 152, "1 OR TAP BELOW: BUY", WHITE, 1)
	}
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 14, "S OR TAP TOP: BACK", GRAY, 1)
	draw_text_right(f, WIDTH - PANEL_X - 6, PANEL_Y + PANEL_H - 14, "Z: FLY", GRAY, 1)
}

draw_menu :: proc(g: ^Game, f: ^Frame) {
	buf: [40]u8
	fill(f, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, BLACK)
	fill(f, PANEL_X, PANEL_Y, PANEL_W, 1, GRAY)
	fill(f, PANEL_X, PANEL_Y + PANEL_H - 1, PANEL_W, 1, GRAY)
	if g.show_board {
		draw_board(g, f)
		return
	}
	if g.show_shop {
		draw_shop(g, f)
		return
	}
	// Rows from the top of the panel down: logo, crash report (or tagline), the rules, the bank, then the footer.
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
	lines := MENU_LINES
	y := 106
	for line, i in lines {
		draw_text_centered(f, y, line, i == 0 ? WHITE : GRAY, 1)
		y += 11
	}
	draw_text_centered(f, PANEL_Y + PANEL_H - 38, itoa(buf[:], "BANK $", g.bank), GOLD, 1)
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 26, "B OR TAP TOP: SCORES", GRAY, 1)
	draw_text(f, PANEL_X + 6, PANEL_Y + PANEL_H - 14, "S OR TAP 2ND BAND: SHOP", GRAY, 1)
	draw_text_right(f, WIDTH - PANEL_X - 6, PANEL_Y + PANEL_H - 14, g.muted ? "M: SOUND OFF" : "M: MUTE", GRAY, 1)
}
