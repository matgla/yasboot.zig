//! yasboot is always built the way the device builds code: Zig's C backend
//! writes the loader as C and tcc compiles and links that.  No LLVM, clang,
//! gcc or binutils step.  Two modes share the loader (src/yasboot.zig):
//!
//!   -Dmode=baremetal  (default) the bootloader: -nostdinc against include/,
//!                     linked with link/<board>.ld into an ELF to flash
//!   -Dmode=yasos      the same logic as a YasOS program (main() on yasos
//!                     libc, a YAFF module), to try it inside a running
//!                     kernel before flashing it
//!
//!   zig build -Dtcc=/path/to/armv8m-tcc [-Dmode=...] [-Doptimize=...]
//!       baremetal: zig-out/bin/yasboot   yasos: zig-out/usr/bin/yasboot
//!       plus the generated C next to it (yasboot.c)
//!   zig build run     boot the bare-metal loader on QEMU mps3-an524
//!
//! Inside yasos.zig, `zig build yasboot` builds both modes with the kernel's
//! cross tcc and `zig build yasboot-test` runs the program in the kernel.

const std = @import("std");

pub const Mode = enum { baremetal, yasos };
pub const Board = enum { qemu_mps3_an524 };

pub fn build(b: *std.Build) void {
    // small unless asked otherwise: the loader has a size budget.
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default small)") orelse .small;
    const mode = b.option(Mode, "mode", "baremetal (the bootloader, default) or yasos (a program to run in the kernel)") orelse .baremetal;
    const board = b.option(Board, "board", "Board for -Dmode=baremetal (default qemu_mps3_an524)") orelse .qemu_mps3_an524;
    const tcc = b.option(std.Build.LazyPath, "tcc", "ARM cross tcc (default: armv8m-tcc from PATH)");

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m33 },
        .ofmt = .c,
    });

    // 1. Zig -> C.  The root is the platform; it imports the loader.
    const core = b.createModule(.{ .root_source_file = b.path("src/yasboot.zig") });
    const cbe = b.addObject(.{
        .name = "yasboot",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/platform/{s}.zig", .{@tagName(mode)})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yasboot", .module = core }},
        }),
        .use_llvm = false,
    });
    cbe.bundle_compiler_rt = false;
    const c_src = cbe.getEmittedBin();

    // 2. C -> object.  Bare metal sees only include/ (-nostdinc), so neither
    //    tcc's configured libc nor the host's leaks in; the program builds
    //    against the yasos libc headers tcc is configured with.
    const compile = tccCommand(b, tcc);
    compile.addArgs(&.{ tccOpt(optimize), "-ffunction-sections", "-fdata-sections" });
    switch (mode) {
        .baremetal => {
            compile.addArgs(&.{ "-nostdinc", "-fno-pic", "-mfloat-abi=soft" });
            compile.addPrefixedDirectoryArg("-I", b.path("include"));
        },
        .yasos => compile.addArg("-fvisibility=hidden"),
    }
    compile.addPrefixedDirectoryArg("-I", b.graph.path(.zig_lib, ""));
    compile.addArg("-include");
    compile.addFileArg(b.path("include/zig_c_prelude.h"));
    compile.addArg("-MD");
    _ = compile.addPrefixedDepFileOutputArg("-MF", "yasboot.d");
    compile.addArg("-c");
    compile.addFileArg(c_src);
    compile.addArg("-o");
    const obj = compile.addOutputFileArg("yasboot.o");

    // 3. Link.
    const link = tccCommand(b, tcc);
    switch (mode) {
        .baremetal => {
            link.addArgs(&.{ "-nostdlib", "-static", "-Wl,--gc-sections", "-Wl,-oformat=elf32-littlearm" });
            link.addPrefixedFileArg("-T", b.path(b.fmt("link/{s}.ld", .{@tagName(board)})));
        },
        .yasos => link.addArgs(&.{ "-fvisibility=hidden", "-Wl,--gc-sections", "-Wl,-oformat=yaff" }),
    }
    link.addArg("-o");
    const bin = link.addOutputFileArg("yasboot");
    link.addFileArg(obj);

    const dir = switch (mode) {
        .baremetal => "bin",
        .yasos => "usr/bin",
    };
    b.getInstallStep().dependOn(&b.addInstallFile(bin, b.fmt("{s}/yasboot", .{dir})).step);
    b.getInstallStep().dependOn(&b.addInstallFile(c_src, b.fmt("{s}/yasboot.c", .{dir})).step);
    // For a parent build (yasos.zig) to install or run.
    b.addNamedLazyPath("yasboot", bin);
    b.addNamedLazyPath("yasboot.c", c_src);

    const run = b.addSystemCommand(&.{
        "qemu-system-arm",     "-machine",                "mps3-an524", "-nographic",
        "-semihosting-config", "enable=on,target=native", "-kernel",
    });
    run.addFileArg(bin);
    const run_step = b.step("run", "Boot the bare-metal loader on QEMU mps3-an524");
    if (mode == .baremetal) {
        run_step.dependOn(&run.step);
    } else {
        run_step.dependOn(&b.addFail("-Dmode=yasos builds a YasOS program: run it in the kernel (yasos.zig: zig build yasboot-test)").step);
    }
}

/// A tcc command.  A tcc given as -Dtcc is a file argument, so it is hashed
/// and rebuilding the compiler rebuilds the loader.
fn tccCommand(b: *std.Build, tcc: ?std.Build.LazyPath) *std.Build.Step.Run {
    const lp = tcc orelse return b.addSystemCommand(&.{"armv8m-tcc"});
    const run = std.Build.Step.Run.create(b, "tcc");
    run.addFileArg(lp);
    return run;
}

fn tccOpt(optimize: std.builtin.OptimizeMode) []const u8 {
    return switch (optimize) {
        .debug => "-O0",
        .small => "-Os",
        .fast, .safe => "-O2",
    };
}
