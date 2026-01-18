const std = @import("std");

fn isGitRepo(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    defer dir.close();
    if (dir.openDir(".git", .{}) catch null != null)
        return true;
    if (dir.openFile(".git", .{}) catch null != null)
        return true;
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, ".git"))
        return false;
    const has_refs = dir.openDir("refs", .{}) catch null;
    const has_head = dir.openFile("HEAD", .{}) catch null;
    return has_refs != null and has_head != null;
}

/// Run `git <args>` in a repo, printing stdout line by line
fn runGitInRepo(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    args: [][]const u8,
) !void {
    const repo_name = std.fs.path.basename(repo_path);
    std.debug.print("{s}: git", .{repo_name});
    for (args) |arg|
        std.debug.print(" {s}", .{arg});
    std.debug.print("\n", .{});
    var exec_args = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(exec_args);
    exec_args[0] = "git";
    for (args, 0..) |a, i|
        exec_args[i + 1] = a;
    var child = std.process.Child.init(exec_args, allocator);
    child.cwd = repo_path;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    var stdout_file = child.stdout.?;
    var line_buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer line_buf.deinit(allocator);
    var chunk: [1024]u8 = undefined;
    while (true) {
        const n = try stdout_file.read(&chunk);
        if (n == 0)
            break;
        for (chunk[0..n]) |c| {
            if (c == '\n') {
                std.debug.print("{s}\n", .{line_buf.items});
                line_buf.clearRetainingCapacity();
            } else {
                try line_buf.append(allocator, c);
            }
        }
    }
    if (line_buf.items.len > 0)
        std.debug.print("{s}\n", .{line_buf.items});
    const term = try child.wait();
    if (term != .Exited or term.Exited != 0)
        std.process.exit(if (term == .Exited) term.Exited else 1);
    std.debug.print("\n", .{});
}

fn gitWalk(allocator: std.mem.Allocator, root: []const u8, args: [][]const u8) !void {
    if (isGitRepo(root)) {
        try runGitInRepo(allocator, root, args);
        return;
    }
    var dir = std.fs.openDirAbsolute(root, .{}) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory)
            continue;
        if (std.mem.eql(u8, entry.name, ".git"))
            continue;
        const child_path = try std.fs.path.join(allocator, &[_][]const u8{ root, entry.name });
        defer allocator.free(child_path);
        try gitWalk(allocator, child_path, args);
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
    var args = try allocator.alloc([]const u8, raw_args.len - 1);
    defer allocator.free(args);
    for (raw_args[1..], 0..) |a, i|
        args[i] = a;
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    try gitWalk(allocator, cwd, args);
}
