const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });
    const mod = b.addModule("zig_hopefox", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    //const chess_mod = b.createModule(.{ .root_source_file = b.path("src/gof/chess/types.zig") });

    const exe = b.addExecutable(.{
        .name = "zig_hopefox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_hopefox", .module = mod },
                //.{ .name = "chess", .module = chess_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    //mod_tests.root_module.addImport("chess", chess_mod);

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    exe_tests.use_llvm = true;

    exe_tests.max_memory = 10000;
    mod_tests.max_memory = 10000;

    exe_tests.root_module.addImport("chess", mod);
    mod_tests.root_module.addImport("chess", mod);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
