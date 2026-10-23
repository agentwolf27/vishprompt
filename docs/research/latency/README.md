# Latency runs

Each CSV is the raw output of one `make verify-latency`: 20 timed runs after one untimed warm-up,
on the Release build, on this Mac. Durations are in milliseconds. Speedup PRs compare their run
against the one before them, using the same harness.

## Baseline · 2026-10-23 · before any speedup

`baseline-2026-10-23.csv`: 20 runs of 4.9 s of speech.

| Stage | Median | p90 |
|---|---|---|
| Post-roll (fixed wait after key-up) | 120 ms | 130 ms |
| Streaming model stop | 5.8 ms | 16 ms |
| Batch transcription (Parakeet v3) | 310 ms | 610 ms |
| Local compile | 18 ms | 56 ms |
| Paste keystroke | 19 ms | 58 ms |
| **Key-up to pasted** | **490 ms** | **870 ms** |

This matches the real dictations in History since the encoder fix (490, 520 and 550 ms, n=3).

**What it changes about the speed plan.** The plan suspected `streaming.stop()` of 0.2–0.3 s.
It costs about 6 ms. The time is in the batch transcription itself: 310 ms here, against
105–143 ms for the same 4.9 s of audio when the batch model runs alone (`make verify-memory`).
Both models run on the Neural Engine, and the streaming model is still loaded and may still be
finishing a chunk when the batch model starts. S1c is aimed there.

## Live preview on against off · 2026-10-23 · interleaved

`preview-ab-2026-10-23.csv`: 40 runs alternating between the streaming preview on and off, in one
run (`TEST_RUNNER_VISPRFLOW_LATENCY_COMPARE=preview make verify-latency`). The load average was
about 8.8, with other apps busy, including `photoanalysisd`, which also uses the Neural Engine.

| Key-up to pasted | Median | p90 | n |
|---|---|---|---|
| Live preview on | 790 ms | 1.5 s | 20 |
| Live preview off | 830 ms | 2.2 s | 20 |

**No measurable cost from the preview.** An earlier pair of separate runs suggested otherwise:
490 ms on, then 260 ms off, minutes later. A third separate run of unchanged code then gave
910 ms. Runs taken minutes apart on a busy Mac are not comparable. From here on, every speedup is
measured interleaved against the old behaviour in the same run, and the load average is quoted.

**Rejected:** waiting for the streaming model's in-flight chunk before the batch transcription.
It gave a median of 1.7 s and p90 of 4.5 s, failing the harness ceiling.
