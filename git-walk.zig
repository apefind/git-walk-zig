const std = @import("std");

fn isGitRepo(path: []const u8) !bool {
    var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var has_refs = false;
    var has_hooks = false;

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".git")) {
            return true;
        }
        if (std.mem.eql(u8, entry.name, "refs")) {
            has_refs = true;
        }
        if (std.mem.eql(u8, entry.name, "hooks")) {
            has_hooks = true;
        }
    }

    return has_refs and has_hooks;
}

fn gitCmd(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.appendSlice("git");
    for (args) |arg| {
        try list.append(' ');
        try list.appendSlice(arg);
    }

    return list.toOwnedSlice();
}

fn gitWalk(
    allocator: std.mem.Allocator,
    root: []const u8,
    cmd: []const u8,
) !void {
    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const child_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ root, entry.name },
        );
        defer allocator.free(child_path);

        if (try isGitRepo(child_path)) {
            std.debug.print("{s}: {s}\n", .{ entry.name, cmd });

            var child_dir = try std.fs.openDirAbsolute(child_path, .{});
            defer child_dir.close();

            const result = try std.ChildProcess.exec(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "sh", "-c", cmd },
                .cwd_dir = child_dir,
            });

            if (result.term.Exited != 0) {
                std.process.exit(result.term.Exited);
            }

            std.debug.print("\n", .{});
        } else {
            try gitWalk(allocator, child_path, cmd);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    if (raw_args.len < 2) return;

    // Convert [:0]u8 → []const u8
    var args = try allocator.alloc([]const u8, raw_args.len - 1);
    defer allocator.free(args);

    for (raw_args[1..], 0..) |a, i| {
        args[i] = std.mem.span(a);
    }

    const cmd = try gitCmd(allocator, args);
    defer allocator.free(cmd);

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    try gitWalk(allocator, cwd, cmd);
}
