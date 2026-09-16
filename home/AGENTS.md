# Global agent instructions

Solo developer. Personal intraday ES futures trading software and research tooling
in `~/dev`. No team and no second reviewer, so correctness beats speed.

## Non-negotiable

- Anything that could reach live trading, order routing, or Rithmic connectivity
  stops and asks first. Say what the blast radius is before touching it.
- Never commit or push unless I ask.
- Never add yourself as commit co-author and never add "Generated with" trailers.
- Never run `darwin-rebuild`. I run rebuilds by hand.
- Ask before anything destructive: deleting files, rewriting git history, `rm -rf`,
  dropping tables, or touching MotiveWave, Bookmap, or Parallels state under
  `~/Library` and `~/Parallels`.

## How to work

- Simplest thing that works end to end. No wrappers, abstraction layers, or config
  systems until the direct path actually breaks.
- Prefer correctness, clarity, and long-term maintainability over development speed.
- Fix bugs by reproducing them first, as close to how I would hit it as possible.
  A fix for an unreproduced bug is a guess.
- Match the surrounding code's style instead of importing your own conventions.
- When uncertain, say so and state your assumption. Do not fill gaps with
  confident-sounding guesses.
- Report honestly: if tests fail, show the output; if you skipped something, say so.

## Market data

- Timestamps are exchange time unless stated otherwise. Be explicit about timezone
  in any code that parses or compares them.
- Never silently drop, pad, or interpolate missing bars or ticks. Surface gaps.

## Maintaining this file

Keep only what is useful to almost every session. Do not repeat what the code
already shows; point at the authoritative file or command. Prefer rewriting or
pruning entries over appending.
