const std = @import("std");

fn isGitRepo(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    defer dir.close();

    // .git may be a directory
    if (dir.openDir(".git", .{}) catch null != null) return true;

    // .git may be a file (worktree/submodules)
    if (dir.openFile(".git", .{}) catch null != null) return true;

    // Bare repository fallback: refs + HEAD
    const hasRefs = dir.openDir("refs", .{}) catch null;
    const hasHead = dir.openFile("HEAD", .{}) catch null;

    if (hasRefs != null and hasHead != null) return true;

    return false;
}

fn gitWalk(
    allocator: std.mem.Allocator,
    root: []const u8,
    args: [][]const u8,
) !void {
    var dir = std.fs.openDirAbsolute(root, .{}) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const child_path = try std.fs.path.join(allocator, &[_][]const u8{ root, entry.name });
        defer allocator.free(child_path);

        if (isGitRepo(child_path)) {
            std.debug.print("{s}: ", .{entry.name});
            // print full git command
            std.debug.print("git", .{});
            for (args) |arg| {
                std.debug.print(" {s}", .{arg});
            }
            std.debug.print("\n", .{});

            // Build argv: ["git", ...args]
            var exec_args = try allocator.alloc([]const u8, args.len + 1);
            defer allocator.free(exec_args);

            exec_args[0] = "git"; // assumes git is in PATH
            for (args, 0..) |a, i| {
                exec_args[i + 1] = a;
            }

            var child = std.process.Child.init(exec_args, allocator);
            child.cwd = child_path;
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Inherit; // print stdout immediately
            child.stderr_behavior = .Inherit; // print stderr immediately

            try child.spawn();
            const term = try child.wait();

            if (term != .Exited or term.Exited != 0) {
                std.process.exit(if (term == .Exited) term.Exited else 1);
            }

            std.debug.print("\n", .{});
        } else {
            try gitWalk(allocator, child_path, args);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    if (raw_args.len < 2) {
        std.debug.print("Usage: git-walk <git-args>\n", .{});
        return;
    }

    const arg_count = raw_args.len - 1;
    var args = try allocator.alloc([]const u8, arg_count);
    defer allocator.free(args);

    // Copy arguments
    for (raw_args[1..], 0..) |a, i| {
        args[i] = a;
    }

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    try gitWalk(allocator, cwd, args);
}
