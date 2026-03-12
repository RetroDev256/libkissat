const std = @import("std");
const LinkMode = std.builtin.LinkMode;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var symbols: ?bool = b.option(bool, "symbols", "add debug symbols");
    var logging: ?bool = b.option(bool, "logging", "include logging code");
    const asan = b.option(bool, "asan", "enable address sanitizer") orelse false;
    const lto = b.option(bool, "lto", "enable link time optimization") orelse false;

    // ---------------------------------------------------------- Build options

    // Writing through 'popen' can be considered harmful in certain library usage.
    const safe = b.option(bool, "safe", "disable the use of writing through 'popen'") orelse false;

    // We have compile time options which save memory and speed up the solver by
    // limiting the size of formulas that can be handled, fix the default
    // configuration, disable messages, profiling and certain statistics.
    var compact = b.option(bool, "compact", "limit watcher stacks and clause arena size") orelse false;
    var opt_no_options = b.option(bool, "no-options", "fix all solver options to their default value");
    var opt_quiet = b.option(bool, "quiet", "disable messages, built-in profiling and metrics");
    const competition = b.option(bool, "competition", "same as '--no-options --quiet'");
    const extreme = b.option(bool, "extreme", "same as '--compact --no-options --quiet'") orelse false;
    var no_proofs = b.option(bool, "no-proofs", "do not include code for proof generation") orelse false;
    const ultimate = b.option(bool, "ultimate", "all configurations above ('--extreme --no-proofs')") orelse false;

    // For '--no-options' (and '--extreme', '--ultimate', and '--competition' too)
    // we allow the following options which enforce a different option at compile
    // time (corresponding to the same run-time settings without '--no-options'):
    const default = b.option(bool, "default", "do not enforce specialized option configurations") orelse false;
    const sat = b.option(bool, "sat", "force options to focus on satisfiable instance") orelse false;
    const unsat = b.option(bool, "unsat", "force options to focus on unsatisfiable instance") orelse false;

    // Redundant metrics and statistics gathering code can be enabled and disabled
    // separately.  Only essential counters are updated and printed without these.
    // Metrics are considered to be statistics, thus  '--metrics' also implies
    // '--statistics' and vice versa '--no-statistics' implies '--no-metrics.
    var metrics = b.option(bool, "metrics", "include metrics code (default with '-g', '-l')");
    var statistics = b.option(bool, "statistics", "include statistics code (default without '--extreme')");

    // For (delta) debugging and testing the parser can read options embedded
    // in DIMACS files.  This feature is enabled for '-c', '-g', and '-l' but
    // disabled for optimized compilation (without '-c', '-g', nor '-l'),
    // except that '--embedded' is also assumed with '--coverage' unless options
    // are disabled (with '--no-options', '--extreme' or '--no-options').
    var embedded = b.option(bool, "embedded", "allow parsing option value pairs in DIMACS file");

    // Enable (very) expensive low-level checkers for data structures:
    const check_all = b.option(bool, "all", "check consistency of all data structures") orelse false;
    const check_heap = b.option(bool, "heap", "check consistency of binary heaps") orelse check_all;
    const check_kitten = b.option(bool, "kitten", "check consistencies in 'Kitten' sub-solver") orelse check_all;
    const check_queue = b.option(bool, "queue", "check consistency of the variable-move-to-front queue") orelse check_all;
    const check_vectors = b.option(bool, "vectors", "check consistency of watch vectors") orelse check_all;
    const check_walk = b.option(bool, "walk", "check consistency of local search") orelse check_all;
    var check: ?bool = b.option(bool, "check", "include assertion checking code");

    // ------------------------------------------ Validating build configuarion

    if (competition == true) {
        if (opt_no_options == false) @panic("`no-options` cannot be specified at the same time as `competition`");
        if (opt_quiet == false) @panic("`quiet` cannot be specified at the same time as `competition`");

        opt_no_options = true;
        opt_quiet = true;
    }

    var no_options = opt_no_options orelse false;
    var quiet = opt_quiet orelse false;

    if (optimize == .Debug) {
        if (check == true) @panic("cannot combine `check` and `Debug`");
        if (logging == true) @panic("cannot combine `logging` and `Debug`");
        if (symbols == true) @panic("cannot combine `symbols` and `Debug`");
        if (metrics == true) @panic("cannot combine `metrics` and `Debug`");
        if (statistics == true) @panic("cannot combine `statistics` and `Debug`");
    }

    if (quiet) {
        if (logging == true) @panic("cannot combine `logging` and `quiet`");
        if (metrics == false) @panic("cannot combine `metrics=false` and `quiet`");
        if (statistics == false) @panic("cannot combine `statistics=false` and `quiet`");
    }

    if (extreme) {
        if (compact) @panic("cannot combine `compact` and and `extreme`");
        if (embedded == true) @panic("cannot combine `embedded` and `extreme`");
        if (logging == true) @panic("cannot combine `logging` and `extreme`");
        if (no_options == true) @panic("cannot combine `no-options` and `extreme`");
        if (quiet) @panic("cannot combine `quiet` and `extreme`");
        if (ultimate) @panic("cannot combine `ultimate` and `extreme`");
        if (metrics == false) @panic("cannot combine `metrics=false` and `extreme`");
        if (statistics == false) @panic("cannot combine `statistics=false` and `extreme`");

        compact = true;
        no_options = true;
        quiet = true;
    }

    if (ultimate) {
        if (compact) @panic("cannot combine `compact` and and `ultimate`");
        if (embedded == true) @panic("cannot combine `embedded` and `ultimate`");
        if (logging == true) @panic("cannot combine `logging` and `ultimate`");
        if (no_options == true) @panic("cannot combine `no-options` and `ultimate`");
        if (no_proofs == true) @panic("cannot combine `no-proofs` and `ultimate`");
        if (quiet) @panic("cannot combine `quiet` and `ultimate`");
        if (metrics == false) @panic("cannot combine `metrics=false` and `ultimate`");
        if (statistics == false) @panic("cannot combine `statistics=false` and `ultimate`");

        compact = true;
        no_options = true;
        no_proofs = true;
        quiet = true;
    }

    if (default and sat) @panic("cannot combine `default` and `sat");
    if (default and unsat) @panic("cannot combine `default` and `unsat`");
    if (sat and unsat) @panic("cannot combine `sat` and `unsat`");

    if (default and !no_options) @panic("cannot use `default` without `no-options`");
    if (sat and !no_options) @panic("cannot use `sat` without `no-options`");
    if (unsat and !no_options) @panic("cannot use `unsat` without `no-options`");

    if (no_options and embedded == true) @panic("cannot combine `no-options` and `embedded`");

    // -------------------------------------------- Defaulting on configuration

    if (metrics == null) {
        if (statistics == false) {
            metrics = false;
        } else if (optimize == .Debug or logging == true) {
            metrics = true;
        } else {
            metrics = false;
        }
    } else if (metrics == true) {
        if (logging == true) @panic("cannot combine `metrics` and `logging`");
    } else {
        if (optimize != .Debug and logging == false)
            @panic("cannot combine `metrics=false` without `Debug` or `logging`");
    }

    if (statistics == null) {
        if (metrics.? or optimize == .Debug or logging == true) {
            statistics = true;
        } else {
            statistics = false;
        }
    } else if (statistics == true and logging == true) {
        @panic("cannot combine `metrics` and `logging`");
    }

    if (check_heap) check = true;
    if (check_kitten) check = true;
    if (check_queue) check = true;
    if (check_queue) check = true;
    if (check_vectors) check = true;
    if (check_walk) check = true;

    if (embedded == null) {
        if (no_options) {
            embedded = false;
        } else if (check == true or optimize == .Debug or logging == true) {
            embedded = true;
        } else {
            embedded = false;
        }
    } else if (embedded == true) {
        if (check == true) @panic("cannot combine `check` and `embedded`");
        if (optimize == .Debug) @panic("cannot combine `Debug` and `embedded`");
        if (logging == true) @panic("cannot combine `logging` and `embedded`");
    } else if (check == false and optimize != .Debug and logging == false) {
        @panic("cannot use `embedded=false` without `check`, `Debug` nor `logging`");
    }

    if (quiet) logging = false;
    symbols = symbols orelse (optimize == .Debug);
    logging = logging orelse (optimize == .Debug);
    check = check orelse (optimize == .Debug);

    // ------------------------------------------------------------ Compilation

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("libkissat.h"),
        .optimize = optimize,
        .target = target,
    });

    if (asan) translate_c.defineCMacro("ASAN", null);
    if (lto) translate_c.defineCMacro("LTO", null);
    if (check_heap) translate_c.defineCMacro("CHECK_HEAP", null);
    if (check_kitten) translate_c.defineCMacro("CHECK_KITTEN", null);
    if (check_queue) translate_c.defineCMacro("CHECK_QUEUE", null);
    if (check_vectors) translate_c.defineCMacro("CHECK_VECTORS", null);
    if (check_walk) translate_c.defineCMacro("CHECK_WALK", null);
    if (compact) translate_c.defineCMacro("COMPACT", null);
    if (embedded.?) translate_c.defineCMacro("EMBEDDED", null);
    if (!quiet and logging.?) translate_c.defineCMacro("LOGGING", null);
    if (!check.?) translate_c.defineCMacro("NDEBUG", null);
    if (metrics.?) translate_c.defineCMacro("METRICS", null);
    if (no_options) translate_c.defineCMacro("NOPTIONS", null);
    if (no_proofs) translate_c.defineCMacro("NPROOFS", null);
    if (quiet) translate_c.defineCMacro("QUIET", null);
    if (safe) translate_c.defineCMacro("SAFE", null);
    if (sat) translate_c.defineCMacro("SAT", null);
    if (statistics.? and !metrics.?) translate_c.defineCMacro("STATISTICS", null);
    if (unsat) translate_c.defineCMacro("UNSAT", null);

    const kissat_c = b.dependency("kissat_c", .{});
    translate_c.addIncludePath(kissat_c.path("src"));
    _ = translate_c.addModule("libkissat");
    translate_c.link_libc = true;
}
