# Detecting terminal size over a serial line

A raw UART carries no window size, so the only way to learn it is to ask the
terminal emulator. This is the Cursor Position Report (CPR) handshake that
`libs/yasos_curses` (`detect_terminal_size()`) uses.

## Sequence

Send, in one write:

```
ESC [ 9 9 9 ; 9 9 9 H     move cursor to row 999, col 999 (terminal clamps to its real extent)
ESC [ 6 n                 Device Status Report: ask for the cursor position
```

C string: `"\033[999;999H\033[6n"`

The terminal replies on the input side:

```
ESC [ <rows> ; <cols> R
```

Because the cursor was clamped to the bottom-right corner, `<rows>` and
`<cols>` are the terminal size.

## Procedure

1. Put the input in raw mode so the reply arrives verbatim: no `ICANON`, no
   `ECHO`, no `ICRNL`/`INLCR`/`IGNCR`, and output post-processing off.
2. Make reads non-blocking.
3. Write the query above.
4. Read bytes until `R` arrives or about 250 ms have passed.
5. Restore the previous termios and file flags.
6. Skip bytes up to the first `ESC`, expect `[`, then parse `rows`, `;`, `cols`.
7. Accept only if both values are in 2..1000; otherwise keep the 24x80 default.

If the terminal does not answer (dumb pipe, no CPR support), keep the default.

## Notes

- The kernel's `TIOCGWINSZ` on the UART file is hardcoded to 24x80
  (`source/kernel/drivers/uart/uart_file.zig`), so userspace has to do this.
- Restore the cursor position afterwards if the caller cares; the query leaves
  the cursor in the bottom-right corner (curses clears the screen right after).
- Reference implementation: `libs/yasos_curses/curses.c`, `detect_terminal_size()`.
