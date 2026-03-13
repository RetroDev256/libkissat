1. Example build.zig.zon
```zig
// Run `zig fetch --save git+https://github.com/RetroDev256/libkissat` to add the dependency automatically

.{
    .name = .general,
    .version = "0.0.0",
    .dependencies = .{
        .libkissat = .{
            .url = "git+https://github.com/RetroDev256/libkissat#17e590bdd9e5b463cf95c4e35983884372de4982",
            .hash = "libkissat-4.0.4-sTTXPS82AADf9n8wthjGQmI2ci5AuOz_3ThkM1kql53Y",
        },
    },
    .fingerprint = 0xce29364abca0a002,
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```
3. Example build.zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const libkissat = b.dependency("libkissat", .{
        .optimize = optimize,
        .target = target,
        .quiet = true,
    });

    const exe = b.addExecutable(.{
        .name = "general",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .imports = &.{
                .{ .name = "kissat", .module = libkissat.module("libkissat") },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
```
3. Example `src/main.zig`:

```zig
const std = @import("std");
const kissat = @import("kissat");

pub fn main() !void {
    const solver = kissat.kissat_init() orelse return error.FailedToInitialize;
    defer kissat.kissat_release(solver); // frees memory related to the solver

    // Add CNF clauses, eg. 2 0
    kissat.kissat_add(solver, 2);
    kissat.kissat_add(solver, 0);

    // SAT-solve the clauses
    const result = kissat.kissat_solve(solver);

    switch (result) {
        0 => std.debug.print("Solving interrupted\n", .{}),
        10 => std.debug.print("Problem is SAT\n", .{}),
        20 => std.debug.print("Problem is UNSAT\n", .{}),
        else => unreachable,
    }

    std.debug.print("Value of variable 2: {}\n", .{
        kissat.kissat_value(solver, 2) > 0,
    });
}
```
