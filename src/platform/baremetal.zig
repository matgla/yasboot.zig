//! yasboot on bare metal: the bootloader proper.  Startup (vector table,
//! .data/.bss), the console UART and the end of a run; the loader logic is
//! src/yasboot.zig.  Board: QEMU mps3-an524 for now.

const std = @import("std");
const yasboot = @import("yasboot");

/// CMSDK APB UART0 of the an524 (QEMU's serial console).
const Uart = extern struct {
    data: u32,
    state: u32,
    ctrl: u32,
    intstatus: u32,
    bauddiv: u32,
};
const uart0: *volatile Uart = @ptrFromInt(0x41303000);
const state_tx_full: u32 = 1 << 0;
const ctrl_tx_enable: u32 = 1 << 0;

fn putc(c: u8) void {
    while (uart0.state & state_tx_full != 0) {}
    uart0.data = c;
}

fn uartWrite(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') putc('\r');
        putc(c);
    }
}

/// Ends the QEMU run with `code` (semihosting SYS_EXIT_EXTENDED); on a
/// debugger-less board the BKPT faults, so only call this under QEMU.
fn qemuExit(code: u32) noreturn {
    const block = [2]u32{ 0x20026, code }; // ADP_Stopped_ApplicationExit
    asm volatile ("bkpt #0xab"
        :
        : [op] "{r0}" (@as(u32, 0x20)),
          [arg] "{r1}" (&block),
        : .{ .memory = true });
    while (true) {}
}

pub const panic = std.debug.FullPanic(panicFn);

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    uartWrite("yasboot: panic: ");
    uartWrite(msg);
    uartWrite("\n");
    while (true) {}
}

// Linker-script symbols (link/*.ld).  No leading "__": Zig's C backend
// renames extern variables with C-reserved names (zig_e_ prefix) without
// keeping their link name, and the link would not find them.
extern const yasboot_stack_top: anyopaque;
extern var yasboot_data_start: u8;
extern var yasboot_data_end: u8;
extern const yasboot_data_load: u8;
extern var yasboot_bss_start: u8;
extern var yasboot_bss_end: u8;

/// Initial SP and the reset handler; the core reads both from VTOR at reset.
export const vectors linksection(".vectors") = [2]*const anyopaque{
    &yasboot_stack_top,
    @ptrCast(&_start),
};

export fn _start() callconv(.c) noreturn {
    const data_len = @intFromPtr(&yasboot_data_end) - @intFromPtr(&yasboot_data_start);
    const data: [*]u8 = @ptrCast(&yasboot_data_start);
    const load: [*]const u8 = @ptrCast(&yasboot_data_load);
    for (0..data_len) |i| data[i] = load[i];
    const bss_len = @intFromPtr(&yasboot_bss_end) - @intFromPtr(&yasboot_bss_start);
    const bss: [*]volatile u8 = @ptrCast(&yasboot_bss_start);
    for (0..bss_len) |i| bss[i] = 0;
    main();
}

const Platform = struct {
    pub const name = "baremetal";

    pub fn puts(_: Platform, s: []const u8) void {
        uartWrite(s);
    }
};

fn main() noreturn {
    uart0.bauddiv = 16;
    uart0.ctrl = ctrl_tx_enable;
    qemuExit(yasboot.run(Platform{}));
}
