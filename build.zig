const std = @import("std");

const EXAMPLES: []const u8 = "./examples/";
fn addExample(
    b: *std.Build,
    name: []const u8,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) !*std.Build.Step {
    var executable = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(b.pathJoin(&.{ EXAMPLES, name })),
        .target = target,
    });
    executable.root_module.addImport("source", module);

    const step_name = try std.fmt.allocPrint(b.allocator, "example-{s}", .{name});
    const step_desc = try std.fmt.allocPrint(b.allocator, "Build and run the example '{s}'", .{name});
    const step = b.step(step_name, step_desc);
    const artifact = b.addInstallArtifact(executable, .{});
    step.dependOn(&artifact.step);

    return step;
}

fn examplesStep(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) !*std.Build.Step {
    var examples_dir = try std.fs.cwd().openDir(EXAMPLES, .{ .iterate = true });
    defer examples_dir.close();

    const all_step = b.step("examples", "Build all examples");

    var it = examples_dir.iterate();
    while (true) {
        const example = it.next() catch |err| {
            std.log.warn("Could not access examples file: {}", .{err});
            continue;
        } orelse break;

        if (addExample(b, example.name, module, target)) |step| {
            all_step.dependOn(step);
        } else |err| {
            std.log.warn("Could not add step for example '{s}': {}", .{ example.name, err });
        }
    }

    return all_step;
}

fn testsStep(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) *std.Build.Step {
    _ = module;
    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for (
        [_]std.builtin.OptimizeMode{ .Debug, .ReleaseFast, .ReleaseSafe, .ReleaseSmall },
    ) |test_mode| {
        const mode_str = @tagName(test_mode);
        const tests = b.addTest(.{
            .name = mode_str ++ " ",
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = test_mode,
        });

        const run_test_step = b.addRunArtifact(tests);
        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&run_test_step.step);
        test_all_step.dependOn(test_step);
    }

    const units = b.addTest(.{
        .root_source_file = b.path("src/source.zig"),
    });
    test_all_step.dependOn(&units.step);

    return test_all_step;
}

pub fn build(b: *std.Build) void {
    const module = b.addModule("source-zig", .{ .root_source_file = b.path("src/source.zig") });
    const target = b.standardTargetOptions(.{});

    const examples_step = examplesStep(b, module, target) catch |err| blk: {
        std.log.warn("Could not build examples: {}", .{err});
        break :blk null;
    };
    const tests_step = testsStep(b, module, target);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(tests_step);
    if (examples_step) |step| all_step.dependOn(step);
    b.default_step.dependOn(all_step);
}
