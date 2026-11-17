# Contributing to ImmerseMe: Weather

Thanks for helping! Bug reports and pull requests are welcome.

## The rules

- **Never push to `main`.** Make a branch, open a pull request, and merge it once the checks pass.
- **Squash-merge** pull requests, so each one becomes a single commit on `main`.
- **The pull request title decides the version.** Start it with a type, a colon and a space:

| Title starts with | Release | Example |
|---|---|---|
| `refactor:` | major, 1.4.2 → 2.0.0 | `refactor: new settings format` |
| `feat:` | minor, 1.4.2 → 1.5.0 | `feat: frost on the readout` |
| `fix:` or `perf:` | patch, 1.4.2 → 1.4.3 | `fix: tooltip shows the wrong moon` |
| `docs:` `chore:` `ci:` `test:` `build:` `style:` | no release | `docs: clearer install steps` |

A scope is fine too: `fix(tooltip): ...`. The "PR title" check fails on anything else.

## What happens when you merge

The **Release** workflow reads the merged pull request's title, bumps the version from the latest
`vX.Y.Z` tag, runs the tests, builds the addon zip and publishes a GitHub release with the zip
attached. The release notes are the title plus the pull request description, so write the
description for players. Nothing is committed back to `main` and nothing is uploaded to
CurseForge: upload the release zip there by hand.

The `.toc` in the repository says `## Version: @project-version@`; the real number is written
into the zip.

Every pull request also gets a **Package preview** download (under the run's *Artifacts*). Extract
it into `Interface/AddOns` to try the change in game.

## Working locally

- Tests: `lua tests/run.lua` from the repository root (plain Lua, no dependencies). CI runs them
  with Lua 5.1, the game's version.
- Try it in game: copy the files into
  `World of Warcraft/_forever_/Interface/AddOns/ImmerseMe_Weather/` and `/reload`. New texture
  files need a full client restart.
- Build a release zip yourself: `python3 .github/scripts/release.py package --version 1.2.3`
  (writes `dist/`; it packages the last commit, not uncommitted changes).

## Project layout

```
ImmerseMe_Weather.toc   addon manifest
Data.lua                climates, zone -> climate map, sky conditions, orb colours (safe to edit)
Core.lua                the weather simulation (pure logic, no frames)
UI.lua                  orb, readout, tooltip, slash commands
Media/                  generated textures (TGA)
tools/make_icons.py     generates every texture in Media/
tools/preview_icons.py  renders docs/images/icons.png from Media/
tools/make_avatar.py    renders the icon at 512 px: docs/images/avatar.png (CurseForge)
tests/                  lua tests/run.lua
docs/                   documentation
```

Every file is plain Lua 5.1 (the addon) or plain Python 3 (the tools). Only the addon files go
into the release zip; `docs/`, `tools/`, `tests/` and `.github/` stay out (see `.gitattributes`).
