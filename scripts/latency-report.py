#!/usr/bin/env python3
"""Latency of real dictations, from History. Read-only; never prints what was said.

    python3 scripts/latency-report.py                 # everything in History
    python3 scripts/latency-report.py --since 2026-10-23
    python3 scripts/latency-report.py --self-test     # checks this script on made-up rows

Groups by destination, level and provider, and reports key-up to the text landing (the
`pasted` mark where it exists, `inserted` before it did): median and p90 with n. Fewer than
five dictations in a group are listed, not summarised, because a percentile of three numbers
is not a statistic.
"""
import argparse
import math
import os
import sqlite3
import sys
from collections import defaultdict

DEFAULT_DB = os.path.expanduser("~/Library/Application Support/Visprflow/visprflow.sqlite")
MIN_FOR_SUMMARY = 5


def percentile(values, p):
    """Nearest rank: a value that was measured, never an interpolation."""
    ordered = sorted(values)
    rank = max(1, math.ceil(p * len(ordered)))
    return ordered[rank - 1]


def fmt(ms):
    """Two significant figures below a second, one decimal above: no fake precision."""
    if ms <= 0:
        return "0 ms"
    if ms >= 1000:
        return f"{ms / 1000:.1f} s"
    magnitude = math.floor(math.log10(ms))
    factor = 10 ** (magnitude - 1)
    rounded = round(ms / factor) * factor
    if rounded >= 1000:
        return f"{rounded / 1000:.1f} s"
    return f"{int(rounded)} ms" if rounded >= 10 else f"{rounded:.1f} ms"


def collect(conn, since=None):
    has_provider = any(row[1] == "provider" for row in conn.execute("PRAGMA table_info(dictation)"))
    provider = "d.provider" if has_provider else "NULL"
    where = "WHERE d.createdAt >= ?" if since else ""
    args = (since,) if since else ()
    rows = conn.execute(
        f"""SELECT d.id, d.destination, d.level, {provider}, s.stage, s.offsetMs
            FROM dictation d JOIN stageTiming s ON s.dictationId = d.id {where}""",
        args,
    ).fetchall()
    by_dictation = defaultdict(lambda: {"marks": {}})
    for dictation_id, destination, level, prov, stage, offset in rows:
        entry = by_dictation[dictation_id]
        entry["key"] = (destination, level, prov or "unrecorded")
        entry["marks"][stage] = offset
    groups = defaultdict(list)
    for entry in by_dictation.values():
        marks = entry["marks"]
        end = marks.get("pasted", marks.get("inserted"))
        if "keyUp" in marks and end is not None and end > marks["keyUp"]:
            groups[entry["key"]].append(end - marks["keyUp"])
    return groups


def report(groups, out=sys.stdout):
    if not groups:
        print("No dictations with key-up and insert marks yet.", file=out)
        return
    print(f"{'destination':<12} {'level':<16} {'provider':<13} {'n':>3}  key-up to text landing", file=out)
    for (destination, level, provider), values in sorted(groups.items()):
        n = len(values)
        if n < MIN_FOR_SUMMARY:
            detail = "too few to summarise: " + ", ".join(fmt(v) for v in sorted(values))
        else:
            detail = f"median {fmt(percentile(values, 0.5))}, p90 {fmt(percentile(values, 0.9))}"
        print(f"{destination:<12} {level:<16} {provider:<13} {n:>3}  {detail}", file=out)


def self_test():
    import io
    conn = sqlite3.connect(":memory:")
    conn.executescript("""
        CREATE TABLE dictation (id TEXT PRIMARY KEY, createdAt TEXT, destination TEXT, level TEXT,
            rawTranscript TEXT, compiledText TEXT, requestJSON TEXT, status TEXT, provider TEXT);
        CREATE TABLE stageTiming (id INTEGER PRIMARY KEY, dictationId TEXT, stage TEXT,
            offsetMs REAL, sinceLastMs REAL);
    """)
    for i in range(10):
        conn.execute("INSERT INTO dictation VALUES (?, '2026-10-23', 'message', 'light', 'secret words', 'x', NULL, 'inserted', 'local')", (f"d{i}",))
        conn.execute("INSERT INTO stageTiming (dictationId, stage, offsetMs, sinceLastMs) VALUES (?, 'keyUp', 1000, 0)", (f"d{i}",))
        conn.execute("INSERT INTO stageTiming (dictationId, stage, offsetMs, sinceLastMs) VALUES (?, 'pasted', ?, 0)", (f"d{i}", 1000 + 100 * (i + 1)))
    conn.execute("INSERT INTO dictation VALUES ('e', '2026-10-23', 'claude_code', 'full', 'secret', 'x', NULL, 'inserted', 'subscription')")
    conn.execute("INSERT INTO stageTiming (dictationId, stage, offsetMs, sinceLastMs) VALUES ('e', 'keyUp', 0, 0)")
    conn.execute("INSERT INTO stageTiming (dictationId, stage, offsetMs, sinceLastMs) VALUES ('e', 'inserted', 6400, 0)")
    groups = collect(conn)
    assert sorted(groups[("message", "light", "local")]) == [100.0 * (i + 1) for i in range(10)]
    buffer = io.StringIO()
    report(groups, buffer)
    text = buffer.getvalue()
    assert "median 500 ms, p90 900 ms" in text, text
    assert "too few to summarise: 6.4 s" in text, text
    assert "secret" not in text, "transcripts must never be printed"
    assert fmt(999.6) == "1.0 s" and fmt(210.4) == "210 ms" and fmt(8.73) == "8.7 ms"
    assert percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], 0.9) == 18
    print("latency-report self-test passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", default=DEFAULT_DB)
    parser.add_argument("--since", help="only dictations on or after this date, YYYY-MM-DD")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not os.path.exists(args.db):
        print(f"No history at {args.db}. Dictate something first.", file=sys.stderr)
        return 1
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    report(collect(conn, args.since))
    return 0


if __name__ == "__main__":
    sys.exit(main())
