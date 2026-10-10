//! yasboot as a YasOS program: the same loader logic on top of yasos libc,
//! so it can be run inside the kernel (scripts/qemu_mount.py, or on a board
//! over transfer.py) before it is flashed as the bootloader.

const std = @import("std");
const yasboot = @import("yasboot");

extern fn write(fd: c_int, buf: [*]const u8, len: usize) isize;
extern fn exit(status: c_int) noreturn;

const Platform = struct {
    pub const name = "yasos";

    pub fn puts(_: Platform, s: []const u8) void {
        var rest = s;
        while (rest.len > 0) {
            const n = write(1, rest.ptr, rest.len);
            if (n <= 0) return;
            rest = rest[@intCast(n)..];
        }
    }
};

export fn main(argc: c_int, argv: [*]const [*:0]const u8) c_int {
    _ = argc;
    _ = argv;
    return yasboot.run(Platform{});
}

pub const panic = std.debug.FullPanic(panicFn);

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    const p: Platform = .{};
    p.puts("yasboot: panic: ");
    p.puts(msg);
    p.puts("\n");
    exit(1);
}
