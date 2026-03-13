1. `zig fetch --save "git+https://github.com/RetroDev256/libkissat"`
2. In your build.zig:

```zig
const libkissat = b.dependency("libkissat", .{
    .optimize = optimize,
    .target = target,
    .quiet = true,
});

... b.createModule(.{
    .imports = &.{
        .{
            .name = "kissat",
            .module = libkissat.module("libkissat")
        },
        // ...
    },
    // ...
}),

```
3. In your Zig code:

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
