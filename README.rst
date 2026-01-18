git-walk
********

`git-walk` is a small Zig utility that recursively walks a directory tree and
executes a given `git` command in every Git repository it finds.

It supports:

* Standard Git repositories with a `.git` directory
* Worktrees where `.git` is a file
* Bare repositories (detected via `refs/` and `HEAD`)

This is useful for running the same Git command across many repositories, such
as checking status, pulling changes, or inspecting branches.

Features
========

* Recursively scans directories starting from the current working directory
* Automatically detects Git repositories
* Executes arbitrary Git commands
* Streams stdout and stderr directly to the terminal
* Exits immediately on the first non-zero Git exit code

Usage
=====
Invoke `git-walk` followed by any arguments you would normally pass to `git`::

    git-walk <git-args>

Examples
========
::

    git-walk status
    git-walk pull --rebase
    git-walk fetch --all
    git-walk branch

For each repository found, the tool prints the repository name and the Git
command being executed.

Example output::

    my-repo: git status
    On branch main
    nothing to commit, working tree clean

    another-repo: git status
    On branch develop
    Your branch is behind 'origin/develop' by 2 commits.

Building
--------

This project requires Zig.

Build the executable::

    zig build-exe git-walk.zig

Or run it directly::

    zig run git-walk.zig -- status

Notes
-----

- ``git`` must be available on your ``PATH``
- The directory walk starts at the current working directory
- If a Git command exits with a non-zero status, ``git-walk`` exits with the same

License
-------
MIT
