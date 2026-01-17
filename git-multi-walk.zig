const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    if (raw_args.len < 2) {
        std.debug.print("Usage: git-walk.zig [-f] <git commands...>\n", .{});
        return;
    }

    var start_idx: usize = 1;
    var force: bool = false;
    if (std.mem.eql(u8, raw_args[1], "-f")) {
        force = true;
        start_idx = 2;
    }

    if (raw_args.len <= start_idx) {
        std.debug.print("No Git commands provided.\n", .{});
        return;
    }

    // Collect commands: each argument is a command; multi-word commands must be quoted
    const num_commands = raw_args.len - start_idx;
    var commands: [][]const u8 = try allocator.alloc([]const u8, num_commands);
    defer allocator.free(commands);

    for (raw_args[start_idx..], 0..) |arg, i| {
        commands[i] = arg;
    }

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    try gitWalk(allocator, cwd, commands, force);
}

// ---------- Walk directories recursively ----------
fn gitWalk(
    allocator: std.mem.Allocator,
    root: []const u8,
    commands: [][]const u8,
    force: bool,
) !void {
    var dir = try std.fs.openDirAbsolute(root, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const child_path = try std.fs.path.join(allocator, &[_][]const u8{ root, entry.name });
        defer allocator.free(child_path);

        if (try isGitRepo(child_path)) {
            for (commands) |cmd| {
                std.debug.print("{s}: git {s}\n", .{ entry.name, cmd });

                // Create ArrayList and try to initialize
                var cmd_list = try std.ArrayList([]const u8).initCapacity(allocator, 1);
                defer cmd_list.deinit(allocator);

                // Append the command
                try cmd_list.append(allocator, cmd);

                // Convert to slice of slices
                const cmd_args = cmd_list.items[0..cmd_list.items.len];

                const result = try runGitCommand(allocator, entry.name, child_path, cmd_args, force);
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);
            }
        } else {
            try gitWalk(allocator, child_path, commands, force);
        }
    }
}

// ---------- Check if directory is a Git repo ----------
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

// ---------- Run Git command ----------
fn runGitCommand(
    allocator: std.mem.Allocator,
    name: []const u8,
    cwd: []const u8,
    args: [][]const u8,
    force: bool,
) !std.process.Child.RunResult {
    var child = std.process.Child.init(args, allocator);
    defer child.deinit();

    child.argv = args;
    child.cwd = cwd;
    child.stdout_behavior = .Capture;
    child.stderr_behavior = .Capture;

    const result = try child.spawn();
    const term = try result.wait();

    if (term != .Exited or term.Exited != 0) {
        if (!force) {
            std.debug.print("Command failed in {s}\n", .{name});
            std.process.exit(if (term == .Exited) term.Exited else 1);
        }
    }

    std.debug.print("{s} stdout:\n{s}\n", .{ name, result.stdout });
    std.debug.print("{s} stderr:\n{s}\n", .{ name, result.stderr });

    return result;
}
