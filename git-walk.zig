const std = @import("std");

fn isGitRepo(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    defer dir.close();

    // .git directory
    if (dir.openDir(".git", .{}) catch null != null) return true;

    // .git file (worktrees/submodules)
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
            std.debug.print("{s}: git {s}\n", .{ entry.name, args[0] });

            // Run git command
            var child = std.process.Child.init(args, allocator);
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

    // Slice arguments after program name
    var args: [][]const u8 = raw_args[1..];

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    try gitWalk(allocator, cwd, args);
}
