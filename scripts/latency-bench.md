# End-to-end latency, by hand

`make verify-latency` times everything VishPrompt does after the key comes up, and runs anywhere.
It cannot time the parts a person adds: the microphone, the hotkey, and sound crossing the room.
This benchmark does, using the method of the Talkify benchmark
(github.com/tornikegomareli/talkify-latency-bench), so the numbers compare with its published
ones: superwhisper 216 ms and Wispr Flow 587 ms, measured by Talkify's developer on a MacBook Pro.

It needs the installed app and its permissions, so it is run by a person, not by CI.

1. `make install`, then open VishPrompt and check the menu says "Listening".
2. Open TextEdit, with a new empty document in front.
3. Play a fixed phrase through the Mac's speakers at a fixed volume, holding the trigger while it
   plays, and release when it ends. The phrase used by `verify-latency` is "hey can you send me
   the figma link for the onboarding screens when you get a moment". Generate it once with:

   ```bash
   say -r 175 -o /tmp/phrase.aiff "hey can you send me the figma link for the onboarding screens when you get a moment"
   ```

4. Twenty times, after one warm-up run. Leave the Mac on mains power, with other dictation apps
   quit.
5. Read the timings from History (⌘Y) or all at once:

   ```bash
   python3 scripts/latency-report.py --since 2026-10-23
   ```

   It reports key-up to the paste keystroke (`pasted`), median and p90 with n.

Report the median and p90 with n=20, the Mac's model, and the macOS version. A single run is an
anecdote, not a benchmark.
