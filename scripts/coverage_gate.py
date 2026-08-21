#!/usr/bin/env python3
"""Coverage gate for MEditor CI.

Parses an lcov file (produced by llvm-cov export after llvm-profdata merge),
computes line coverage for Sources/MEditor, dedupes files compiled into more
than one binary, and fails the build if coverage drops below thresholds.

Usage:
    python3 scripts/coverage_gate.py coverage.lcov [--overall-min 15] [--logic-min 40]

Thresholds (defaults match the repo baseline with headroom):
    overall : whole Sources/MEditor  (baseline 17.4%, floor 15%)
    logic   : non-View code          (baseline 46.8%, floor 40%)
"""
import argparse
import collections
import sys

def parse_lcov(path):
    """Return {abs_path: (lines_found, lines_hit)}."""
    records = {}
    current = None
    lf = lh = 0
    for raw in open(path, errors="replace"):
        line = raw.strip()
        if line.startswith("SF:"):
            current = line[3:]
            lf = lh = 0
        elif line.startswith("LF:"):
            lf = int(line[3:])
        elif line.startswith("LH:"):
            lh = int(line[3:])
        elif line == "end_of_record" and current:
            records[current] = (lf, lh)
            current = None
    return records

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lcov", help="path to lcov file")
    ap.add_argument("--overall-min", type=float, default=15.0)
    ap.add_argument("--logic-min", type=float, default=40.0)
    ap.add_argument("--source-root", default="Sources/MEditor")
    args = ap.parse_args()

    records = parse_lcov(args.lcov)
    # Keep only app sources; dedupe by path relative to the source root
    # (a file compiled into both the app and the test bundle appears twice).
    by_key = {}
    for path, (lf, lh) in records.items():
        marker = "/" + args.source_root + "/"
        if marker not in path:
            continue
        key = path.split(marker, 1)[1]
        cur = by_key.get(key, [0, 0])
        by_key[key] = [max(cur[0], lf), max(cur[1], lh)]

    if not by_key:
        print("ERROR: no coverage data for " + args.source_root)
        sys.exit(1)

    def stats(pred):
        tot = hit = 0
        for key, (lf, lh) in by_key.items():
            if not pred(key):
                continue
            tot += lf
            hit += lh
        return tot, hit

    ov_tot, ov_hit = stats(lambda k: True)
    lg_tot, lg_hit = stats(lambda k: not k.startswith("Views/"))
    ov_pct = ov_hit / ov_tot * 100 if ov_tot else 0.0
    lg_pct = lg_hit / lg_tot * 100 if lg_tot else 0.0

    print("Sources/MEditor files with coverage data: %d" % len(by_key))
    print("  overall : %6d/%6d lines = %5.1f%%  (floor %.0f%%)" % (ov_hit, ov_tot, ov_pct, args.overall_min))
    print("  logic   : %6d/%6d lines = %5.1f%%  (floor %.0f%%)" % (lg_hit, lg_tot, lg_pct, args.logic_min))

    dirs = collections.defaultdict(lambda: [0, 0])
    for key, (lf, lh) in by_key.items():
        d = key.split("/", 1)[0] if "/" in key else "(root)"
        dirs[d][0] += lf
        dirs[d][1] += lh
    print("")
    print("per-directory:")
    for d, (lf, lh) in sorted(dirs.items(), key=lambda x: -x[1][0]):
        pct = lh / lf * 100 if lf else 0.0
        print("  %-24s %6d/%6d  %5.1f%%" % (d, lh, lf, pct))

    failed = []
    if ov_pct < args.overall_min:
        failed.append("overall %.1f%% < %.0f%%" % (ov_pct, args.overall_min))
    if lg_pct < args.logic_min:
        failed.append("logic (non-view) %.1f%% < %.0f%%" % (lg_pct, args.logic_min))
    if failed:
        print("")
        print("COVERAGE GATE FAILED: " + ", ".join(failed))
        sys.exit(1)
    print("")
    print("Coverage gate passed.")

if __name__ == "__main__":
    main()
