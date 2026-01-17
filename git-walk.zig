const std = @import("std");

fn isGitRepo(path: []const u8) !bool {
    var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var has_refs = false;
    var has_hooks = false;

    var it = dir.iterate();
    while (try it.next()) |e| {
        if (std.mem.eql(u8, e.name, ".git")) return true;
        if (std.mem.eql(u8, e.name, "refs")) has_refs = true;
        if (std.mem.eql(u8, e.name, "hooks")) has_hooks = true;
    }

    return has_refs and has_hooks;
}

fn gitCmd(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer list.deinit(allocator);

    try list.appendSlice(allocator, "git");
    for (args) |arg| {
        try list.append(allocator, ' ');
        try list.appendSlice(allocator, arg);
    }

    return list.toOwnedSlice(allocator);
}

fn gitWalk(
    allocator: std.mem.Allocator,
    root: []const u8,
    cmd: []const u8,
) !void {
    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |e| {
        if (e.kind != .directory) continue;

        const child = try std.fs.path.join(
            allocator,
            &[_][]const u8{ root, e.name },
        );
        defer allocator.free(child);

        if (try isGitRepo(child)) {
            std.debug.print("{s}: {s}\n", .{ e.name, cmd });

            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "sh", "-c", cmd },
                .cwd = child,
            });
            defer {
                allocator.free(result.stdout);
                allocator.free(result.stderr);
            }

            if (result.term != .Exited or result.term.Exited != 0) {
                std.process.exit(
                    if (result.term == .Exited) result.term.Exited else 1,
                );
            }

            std.debug.print("\n", .{});
        } else {
            try gitWalk(allocator, child, cmd);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw);

    if (raw.len < 2) return;

    var args = try allocator.alloc([]const u8, raw.len - 1);
    defer allocator.free(args);

    for (raw[1..], 0..) |a, i| {
        args[i] = std.mem.sliceTo(a, 0);
    }

    const cmd = try gitCmd(allocator, args);
    defer allocator.free(cmd);

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    try gitWalk(allocator, cwd, cmd);
}
