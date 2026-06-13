const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const Platform = struct {
    name: []const u8,
    dependency: []const u8,
    query: std.Target.Query,
};

const platforms = [_]Platform{
    .{ .name = "linux_amd64_gcc4", .dependency = "libduckdb_linux_amd64", .query = .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu } },
    .{ .name = "linux_arm64_gcc4", .dependency = "libduckdb_linux_arm64", .query = .{ .os_tag = .linux, .cpu_arch = .aarch64, .abi = .gnu } },
    .{ .name = "osx_amd64", .dependency = "libduckdb_osx", .query = .{ .os_tag = .macos, .cpu_arch = .x86_64, .abi = .none } },
    .{ .name = "osx_arm64", .dependency = "libduckdb_osx", .query = .{ .os_tag = .macos, .cpu_arch = .aarch64, .abi = .none } },
    .{ .name = "windows_amd64", .dependency = "libduckdb_windows_amd64", .query = .{ .os_tag = .windows, .cpu_arch = .x86_64, .abi = .gnu } },
    .{ .name = "windows_arm64", .dependency = "libduckdb_windows_arm64", .query = .{ .os_tag = .windows, .cpu_arch = .aarch64, .abi = .gnu } },
};

const cflags = [_][]const u8{
    "-Wall",
    "-Wextra",
    "-Werror",
    "-fvisibility=hidden",
};

const append_metadata_py =
    \\import sys
    \\
    \\def pad(value):
    \\    encoded = value.encode('ascii')
    \\    return encoded + b'\x00' * (32 - len(encoded))
    \\
    \\library, out, platform, duckdb_version, extension_version = sys.argv[1:6]
    \\signature = bytes([0, 147, 4, 16]) + b'duckdb_signature' + bytes([128, 4])
    \\footer = (
    \\    signature
    \\    + pad('') + pad('') + pad('')
    \\    + pad('CPP')
    \\    + pad(extension_version)
    \\    + pad(duckdb_version)
    \\    + pad(platform)
    \\    + pad('4')
    \\    + b'\x00' * 256
    \\)
    \\with open(library, 'rb') as source:
    \\    payload = source.read()
    \\with open(out, 'wb') as target:
    \\    target.write(payload + footer)
;

fn detectPlatform() []const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => "linux_amd64_gcc4",
            .aarch64 => "linux_arm64_gcc4",
            else => @compileError("unsupported CPU architecture"),
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "osx_amd64",
            .aarch64 => "osx_arm64",
            else => @compileError("unsupported CPU architecture"),
        },
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "windows_amd64",
            .aarch64 => "windows_arm64",
            else => @compileError("unsupported CPU architecture"),
        },
        else => @compileError("unsupported operating system"),
    };
}

fn findPlatform(name: []const u8) *const Platform {
    for (&platforms) |*platform| {
        if (std.mem.eql(u8, platform.name, name)) return platform;
    }
    std.debug.panic("unknown platform '{s}'", .{name});
}

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const duckdb_version = b.option([]const u8, "duckdb-version", "DuckDB version to build for") orelse "1.2.0";
    const platform_name = b.option([]const u8, "platform", "DuckDB platform to build for") orelse detectPlatform();

    const platform = findPlatform(platform_name);
    const target = b.resolveTargetQuery(platform.query);

    const duckdb = b.lazyDependency(platform.dependency, .{}) orelse return;
    const headers = duckdb.path("");

    const lib = b.addSharedLibrary(.{
        .name = "strduck",
        .root_source_file = b.path("src/strduck.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addCSourceFile(.{ .file = b.path("src/strduck.c"), .flags = &cflags });
    lib.addIncludePath(headers);
    lib.addLibraryPath(headers);
    lib.linkSystemLibrary("duckdb");
    lib.addRPath(headers);
    lib.linkLibC();

    const filename = "strduck.duckdb_extension";

    const metadata = Build.Step.Run.create(b, "append extension metadata");
    metadata.addArgs(&.{ "python3", "-c", append_metadata_py });
    metadata.addArtifactArg(lib);
    const ext_path = metadata.addOutputFileArg(filename);
    metadata.addArgs(&.{
        platform.name,
        b.fmt("v{s}", .{duckdb_version}),
        "v0.2.0",
    });

    const install_dir: Build.InstallDir = .{ .custom = b.fmt("v{s}/{s}", .{ duckdb_version, platform.name }) };
    const install = b.addInstallFileWithDir(ext_path, install_dir, filename);
    b.getInstallStep().dependOn(&install.step);

    const check_step = b.step("check", "Check that the extension compiles");
    check_step.dependOn(&lib.step);

    const test_step = b.step("test", "Run SQL logic tests");
    if (b.graph.host.result.os.tag == target.result.os.tag and
        b.graph.host.result.cpu.arch == target.result.cpu.arch)
    {
        const run = Build.Step.Run.create(b, "sqllogictest");
        run.addArgs(&.{ "python3", "-m", "duckdb_sqllogictest", "--test-dir", "test", "--external-extension" });
        run.addFileArg(ext_path);
        test_step.dependOn(&run.step);
    }
}
