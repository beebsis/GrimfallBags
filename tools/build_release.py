#!/usr/bin/env python3
"""
GrimfallBags release builder.

Copies the addon source (GrimfallBags/, Syndicator335/) into dist/,
stripping Lua comments along the way. Source files are never modified --
this only writes into dist/.

Comment stripping is string-literal-aware (tracks single/double-quoted
strings per line) so it never mistakes "--" inside a string for a real
comment marker. Handles both whole-line comments (dropped entirely) and
inline trailing comments (code kept, comment portion removed). Long-form
[[ ]] strings and --[[ ]] block comments are NOT used anywhere in this
codebase today (verified before writing this) -- if one is ever added,
this script will refuse to touch that file and print a warning instead
of silently mishandling it.

Usage:
    python tools/build_release.py
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIRS = ["GrimfallBags", "Syndicator335"]
DIST_DIR = os.path.join(ROOT, "dist")


def strip_lua_comments(src):
    if "[[" in src:
        return None  # long-bracket string/comment present -- bail, don't guess

    out_lines = []
    for line in src.split("\n"):
        in_str = None
        i = 0
        n = len(line)
        marker_idx = None
        while i < n:
            c = line[i]
            if in_str:
                if c == "\\" and i + 1 < n:
                    i += 2
                    continue
                if c == in_str:
                    in_str = None
                i += 1
                continue
            if c == '"' or c == "'":
                in_str = c
                i += 1
                continue
            if c == "-" and i + 1 < n and line[i + 1] == "-":
                marker_idx = i
                break
            i += 1

        if marker_idx is None:
            out_lines.append(line)
            continue

        code_part = line[:marker_idx].rstrip()
        if code_part == "":
            continue  # whole-line comment -- drop it
        out_lines.append(code_part)

    # Collapse runs of blank lines left behind by dropped comment lines.
    collapsed = []
    for line in out_lines:
        if line == "" and collapsed and collapsed[-1] == "":
            continue
        collapsed.append(line)
    while collapsed and collapsed[0] == "":
        collapsed.pop(0)
    while collapsed and collapsed[-1] == "":
        collapsed.pop()
    return "\n".join(collapsed) + "\n"


def main():
    if os.path.isdir(DIST_DIR):
        shutil.rmtree(DIST_DIR)
    os.makedirs(DIST_DIR)

    stripped, skipped, copied = 0, 0, 0
    for src_dir in SRC_DIRS:
        src_path = os.path.join(ROOT, src_dir)
        if not os.path.isdir(src_path):
            print(f"warning: {src_dir} not found, skipping", file=sys.stderr)
            continue
        for dirpath, _, filenames in os.walk(src_path):
            rel_dir = os.path.relpath(dirpath, ROOT)
            out_dir = os.path.join(DIST_DIR, rel_dir)
            os.makedirs(out_dir, exist_ok=True)
            for name in filenames:
                src_file = os.path.join(dirpath, name)
                out_file = os.path.join(out_dir, name)
                if name.endswith(".lua"):
                    with open(src_file, encoding="utf-8") as f:
                        content = f.read()
                    result = strip_lua_comments(content)
                    if result is None:
                        print(f"warning: {os.path.relpath(src_file, ROOT)} "
                              f"contains a long-bracket string/comment -- "
                              f"copied as-is, NOT stripped", file=sys.stderr)
                        shutil.copy2(src_file, out_file)
                        skipped += 1
                    else:
                        with open(out_file, "w", encoding="utf-8", newline="") as f:
                            f.write(result)
                        stripped += 1
                else:
                    shutil.copy2(src_file, out_file)
                    copied += 1

    print(f"Built {DIST_DIR}")
    print(f"  {stripped} .lua files stripped of comments")
    print(f"  {skipped} .lua files copied as-is (long-bracket content, see warnings above)")
    print(f"  {copied} other files copied as-is")


if __name__ == "__main__":
    main()
