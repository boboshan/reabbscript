# Reabbscript

Standalone Lua actions for REAPER: clipboard naming, item editing, markers, regions, and osu!mania export.

## Install

Use REAPER 7.x. Clipboard actions and osu!mania export also need [SWS/S&M](https://www.sws-extension.org/). Editing and marker actions use native REAPER APIs.

### ReaPack

1. Install [ReaPack](https://reapack.com/).
2. Open **Extensions → ReaPack → Import repositories** and add:

   ```text
   https://github.com/boboshan/reabbscript/raw/main/index.xml
   ```

3. Open **Extensions → ReaPack → Browse packages**, search for **bbs**, and install the actions you want.
4. Find them in **Actions → Show action list** and assign shortcuts if useful.

ReaPack installs published versions from `index.xml`. Unpublished local changes require manual installation.

### Manual / local checkout

Open **Actions → Show action list → New action → Load ReaScript** and select a `.lua` file. Each action is self-contained and needs no shared Lua files. Use a stable location: REAPER remembers the file path.

## Actions

| Category | Action | Behavior | Extra dependency |
| --- | --- | --- | --- |
| Clipboard | [Copy selected take names](Clipboard/bbs_Copy%20selected%20take%20names%20to%20clipboard.lua) | Copies active take names; skips items without a take. | SWS |
| Clipboard | [Copy selected track names](Clipboard/bbs_Copy%20selected%20track%20names%20to%20clipboard.lua) | Copies actual track names, including blank names. | SWS |
| Clipboard | [Rename selected takes](Clipboard/bbs_Rename%20selected%20takes%20from%20clipboard.lua) | Applies one line per active take; skips items without a take. | SWS |
| Clipboard | [Rename selected tracks](Clipboard/bbs_Rename%20selected%20tracks%20from%20clipboard.lua) | Applies one clipboard line per selected track. | SWS |
| Items Editing | [Move items to new tracks](Items%20Editing/bbs_Move%20selected%20items%20to%20new%20tracks%20by%20name.lua) | Creates one named track per unlocked selected item with a take; preserves folder closures. | None |
| Items Editing | [Reposition with curved gaps](Items%20Editing/bbs_Reposition%20items%20with%20curved%20gap.lua) | Moves batches of selected item groups with fixed or interpolated gaps. | None |
| Items Editing | [Split by reference tracks and delete gaps](Items%20Editing/bbs_Split%20selected%20items%20by%20reference%20tracks%20and%20delete%20gaps.lua) | Keeps selected-item material covered by reference items, including nested folders. | None |
| Markers | [Markers at item starts](Markers/bbs_Add%20take%20marker%20at%20selected%20items%20start.lua) | Adds active-take or project markers at starts plus an offset. | None |
| Markers | [Markers at item ends](Markers/bbs_Add%20take%20marker%20at%20selected%20items%20end.lua) | Adds active-take or project markers at ends plus an offset. | None |
| Markers | [Region per selected track](Markers/bbs_Create%20region%20for%20items%20on%20each%20selected%20track.lua) | Creates one region spanning direct track items, using track name and color. | None |
| Workflow | [Generate osu!mania hit objects](Workflow/bbs_Generate%20Osu%20mania%20chart%20from%20items.lua) | Copies a four-key `[HitObjects]` section. | SWS |

Woosh is not included in this repository or its package catalog. Removing the package does not delete an existing external installation or downloaded models.

## Split selected items by reference tracks

Use reference items as a timing mask for longer recordings or layers:

1. Select the media items to cut.
2. Select the reference tracks while keeping the target items selected.
3. Run **bbs_Split selected items by reference tracks and delete gaps**.
4. One **Undo** restores the operation.

All items on selected tracks contribute to the mask. Selecting a folder includes its own items and every descendant, including nested folders. Selecting both parent and child does not duplicate references.

Overlapping or touching references form a continuous span:

```text
References:  [1------3]
                 [2----------5]       [8---9]
Target:   [0--------------------------------10]
Result:      [1---------------5]       [8---9]
```

There are no cuts at the internal overlap boundaries; only the outside boundaries of merged spans matter. A one-nanosecond tolerance absorbs arithmetic rounding at touching spans and existing target edges.

- **Keep targets outside the reference tracks/folders.** A selected target that is also a reference covers its own duration and remains unchanged.
- Empty references cause a safe no-op. With valid references, targets wholly outside the mask are deleted.
- Locked targets are skipped and counted. Surviving pieces stay selected; other items and track selections are preserved.
- Muted, hidden, and lane items still count as references. This uses item boundaries, not audio-silence detection.
- All splits finish before gap deletion begins. If a split fails, the action stops without deleting gaps; one Undo restores partial edits.
- Native REAPER splits preserve source/take data. Check split fades with your project settings.

The selection workflow follows [X-Raym's reference-track split action](https://github.com/X-Raym/REAPER-ReaScripts/blob/master/Items%20Editing/X-Raym_Split%20selected%20items%20according%20to%20items%20on%20selected%20tracks%20and%20delete%20new%20items%20at%20spaces.lua). This standalone implementation adds recursive folder coverage.

## Clipboard naming

Names follow REAPER's selected-track/item enumeration order, not click order. LF, CRLF, and CR are accepted. Interior blank lines clear names; one final line ending is a terminator. A single newline clears one name. Extra lines are ignored; unmatched targets keep their names. An empty clipboard changes nothing.

Take copy and rename both skip items without active takes. Copy actions encode a blank final name so it survives a copy/paste round trip.

## Curved gaps

The first batch stays anchored. Selected items sharing a positive REAPER group ID form one logical unit; ungrouped items are separate units. **Items per group** means units per batch, not raw item count. Unselected group members stay put.

- **end** measures from the previous batch's latest end; **start** from its earliest start.
- Equal Start/End Gap values give uniform spacing.
- Curve 1 interpolates linearly. Above 1 delays the change; below 1 advances it.
- Negative gaps create overlaps. A locked selected item aborts the whole reposition operation.

The five settings retain the existing `bbs_RepositionGroupsCurvedGap` ExtState section and keys.

## Markers and regions

Marker dialogs accept a name, an offset in **project seconds**, and `t` (take) or `p` (project). Names may be blank. Take positions include source offset and playback rate. Takes with stretch markers are skipped with an explanation; use project markers for warped audio. Take-less items are skipped in take mode.

The region action covers only items directly on each selected track; it does not collect folder children.

## osu!mania export

Name tracks `1`, `2`, `3`, or `4`. Active take names use `type,hitsound`: `1,0` for a tap, `5,0` for a tap with the new-combo flag, or `128,0` for a hold ending at the item end. Hitsound integers range from 0 to 15. Invalid notes are skipped.

The earliest **selected item**, including invalid items, anchors time zero. Export sorts by millisecond timestamp, column, then original order. Paste into an existing beatmap's `[HitObjects]` section; this is not a complete `.osu` file.

## Development and validation

Run from the repository root with Lua 5.4 and Python 3:

```sh
lua tests/run.lua
python tests/validate_repo.py
git diff --check
```

Use `lua5.4` if that is the executable name. Tests run the actual actions with a controlled REAPER API boundary and do not edit an open project. Use a disposable REAPER project to verify split fades, trimmed/rate-adjusted/looped/reversed sources, grouped edits, folder closures, and restoration with one Undo. The local `docs/` folder is ignored by Git.

Package validation needs Ruby and Pandoc:

```sh
gem install reapack-index
reapack-index --check
```

CI runs these checks. Deployment generates the index from committed versions on `main`; tests, docs, and local tooling are excluded from package discovery. See [AGENTS.md](AGENTS.md) for contribution conventions.

## Git and releases

ReaPack source URLs contain commit hashes. Keep published history stable. An explicitly requested history rewrite must retain a recovery bundle, remap source URLs to retained commits with identical file contents, and verify every packaged version. Use focused `fix:`, `feat:`, `docs:`, and `chore:` commits.

For ordinary changes on shared history, incorporate generated index commits without merge noise:

```sh
git fetch origin
git rebase origin/main
```

Do not rebase a rewritten root onto the old remote history. Publishing rewritten history is a separate, explicitly authorized operation.

Every changed action needs a version bump and changelog. Run `reapack-index` after committing action changes; do not invent source hashes or casually rebuild the historical index. Index deployment is serialized and uses an ordinary push.
