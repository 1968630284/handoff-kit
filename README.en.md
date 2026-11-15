# handoff-kit

> Switching agents or sessions is expensive not because of the code, but because someone has to re-explain "where we stopped and what must not be touched".
> One command packages the facts and the stopping point, and hands the next agent a prompt it can paste directly.

[简体中文](README.md) | **English**

## What it solves

In multi-session agent work, lost context means the next person starts by asking: where are we? what is next? which files are off-limits? Verbal handoffs rely on memory, written ones go stale.

This tool splits a handoff in two:

- **Facts are collected automatically**: git branch / HEAD / uncommitted changes, top-level layout, timestamp, environment
- **You write three short sections**: where you stopped, what is next, what must not change (in `.handoff/notes.md`)

`pack` produces a snapshot:

| File | Purpose |
| --- | --- |
| `BOOT.md` | The resume prompt — paste it into the next agent |
| `HANDOFF.md` | Human-readable handoff (facts + notes) |
| `facts.json` | Machine-readable facts |
| `notes.md` | Copy of your notes |
| `manifest.json` | Package inventory |

`check` fails when a package is missing files or when the notes contain something that looks like a secret.

## Quickstart

```powershell
.\handoff.ps1 init
# edit .handoff\notes.md: stopped at / next / constraints

.\handoff.ps1 pack -Note "core layer done, awaiting review"
.\handoff.ps1 boot          # copy the output into the next agent
```

`boot` prints something like:

```
# Resume prompt (paste into the next agent)

You are taking over the project "demo". Read HANDOFF.md in the same folder, then continue from the stopping point below.

- Path: D:\work\demo
- Revision: branch `main`, HEAD `abc1234 fix idle state machine`, 2 dirty files
- Generated: 2026-11-15 20:10:00

## Stopped at
State machine in 40_app.ps1; next step is the regression run.

## Hard constraints
- Do not change the bus protocol

## Rules
1. First restate stopped-at / todo / constraints, then act.
2. Ask when unsure; do not guess.
3. Update .handoff\notes.md after each step.
```

## Commands

| Command | What it does |
| --- | --- |
| `init` | Create `.handoff/` and the notes template |
| `pack [-Note text]` | Collect facts, merge notes, write a package |
| `boot [-Json]` | Print the latest resume prompt |
| `list` | List packages (time, size, note) |
| `check` | Verify the latest package and scan for obvious secrets |

Common option: `-Root <project dir>`, defaults to the current directory.

## Why not another document

Documents depend on discipline and are usually stale by the time you hand off. Here the machine-collectable parts are collected, you write three headings, and every package is an immutable snapshot.

## Trade-offs

- **No server, no dependencies**: `.handoff/` travels with the project
- **No conversation summarization**: only verifiable facts plus three human sentences — no plausible-sounding but stale prose
- **git optional**: works without a repository, just with fewer facts
- **No encryption**: `check` performs a minimal secret-pattern scan only; real secrets belong in environment variables
- **No automatic pruning**: packages are timestamped; deleting them is your call

## Limits

- Requires Windows PowerShell 5.1+ or PowerShell 7
- Does not parse source code or generate project summaries
- The resume prompt is a hint for an agent, not a guarantee that any model obeys it

## Layout

```
handoff.ps1              CLI entry point
tests/Handoff.Tests.ps1  Pester specs (9 cases)
```

## License

MIT
