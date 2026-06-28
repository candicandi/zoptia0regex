const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The library module: a faithful Zig port of Go's regexp package.
    const regex_mod = b.addModule("regex", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests over the whole library.
    const tests = b.addTest(.{
        .root_module = regex_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_tests.step);

    // A small demo executable.
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("regex", regex_mod);
    const demo = b.addExecutable(.{
        .name = "regex-demo",
        .root_module = demo_mod,
    });
    b.installArtifact(demo);
    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| run_demo.addArgs(args);
    const demo_step = b.step("demo", "Run the regex demo (pass: <pattern> <input>)");
    demo_step.dependOn(&run_demo.step);

    // Differential tests against Go's regexp output (golden reference).
    // The curated corpus (src/cases.jsonl) is committed; the large fuzz corpus
    // (src/fuzz.jsonl) is generated on demand by tools/regen.sh.
    // Benchmark (always ReleaseFast). Compare with `cd tools && go run benchgo.go`.
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const bench_exe = b.addExecutable(.{ .name = "regex-bench", .root_module = bench_mod });
    const bench_step = b.step("bench", "Run the Zig benchmark vs the shared corpus (ReleaseFast)");
    bench_step.dependOn(&b.addRunArtifact(bench_exe).step);

    // Scratch-reuse micro-benchmark: re.match (allocating) vs re.matchScratch.
    const bench_scratch_mod = b.createModule(.{
        .root_source_file = b.path("src/bench_scratch.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const bench_scratch_exe = b.addExecutable(.{ .name = "regex-bench-scratch", .root_module = bench_scratch_mod });
    const bench_scratch_step = b.step("bench-scratch", "Benchmark the Scratch reuse API vs allocating match (ReleaseFast)");
    bench_scratch_step.dependOn(&b.addRunArtifact(bench_scratch_exe).step);

    const difftest_step = b.step("difftest", "Differential test vs Go's regexp (curated + fuzz corpora)");
    inline for (.{ "src/difftest.zig", "src/fuzztest.zig", "src/longesttest.zig" }) |src| {
        const mod = b.createModule(.{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });
        const t = b.addTest(.{ .root_module = mod });
        difftest_step.dependOn(&b.addRunArtifact(t).step);
    }
}
