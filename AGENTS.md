# Repository guidance

## Scope

Standalone REAPER Lua actions live in `Clipboard/`, `Items Editing/`, `Markers/`, and `Workflow/`. Each file must remain independently installable through ReaPack or the action list.

Read the action and its tests before editing. Preserve filenames, selection semantics, ExtState keys, and package identities unless explicitly asked to change them. Woosh was deliberately removed; do not restore it incidentally.

## Conventions

- Lua 5.4, two-space indentation, UTF-8, LF, final newline.
- Local variables/functions; no global helpers or changes to `package.path`.
- Self-contained actions. Small duplicated undo/validation helpers are preferable to undeclared runtime dependencies.
- Metadata: `@description`, `@version`, `@author bbs`, `@about`, `@changelog`.
- Bump versions for changed published scripts. Explain behavior/dependencies in `@about` and release changes in `@changelog`.
- Check the exact extension function used before calling it. Clipboard actions require SWS; native editing actions should not gain unnecessary dependencies.
- Show actionable errors. Successful one-shot actions should not interrupt work with success dialogs.

## Editing invariants

- Snapshot selections before changing enumeration order.
- Validate finite inputs and reference coverage before editing a project.
- One explicit undo block for edits; no undo block for no-ops. Use a no-op `defer` to suppress implicit script undo where appropriate.
- Protect mutation with `xpcall` and always balance UI-refresh suppression and undo.
- Check meaningful API failure returns. Explain partial failure and recovery through one Undo.
- Preserve unrelated selections, source/take data, and folder boundaries.
- Do not run tests against the user's live project without authorization.
- Do not migrate persisted settings, rebuild indexes, or repair unrelated application state incidentally.

The splitter merges overlapping/touching spans, includes selected folders' items and all descendants, handles multiple folder closures, and never deletes targets when reference coverage is empty. A target that is also a reference stays fully covered.

Curved gaps move only selected group members and abort for locked selections. Move-to-tracks skips locked/take-less items and transfers negative folder closures onto inserted tracks.

## Verification

Run from the repository root:

```sh
lua tests/run.lua
python tests/validate_repo.py
git diff --check
reapack-index --check
```

Use `lua5.4` where needed. ReaPack validation requires Ruby, the `reapack-index` gem, and Pandoc. State any unavailable/unrun check explicitly.

For behavior changes, add a focused regression exercising the real action at a mocked REAPER boundary and observe it fail before fixing. Keep tests in `tests/`; no production test hooks. Assert outcomes, item timing, selection, failure handling, and undo cleanup rather than implementation text.

The mock suite cannot establish native split fades, grouped-edit interactions, reversed/looped source behavior, or UI rendering. Check those behaviors in a disposable REAPER project and distinguish native results from automated tests. Keep `docs/` local and untracked; retain README.md and AGENTS.md in version control.

## Packages and Git

- `.reapack-index.conf` excludes tests, docs, and local tooling.
- Preserve published source URLs and their referenced Git objects. An explicitly authorized history rewrite must retain a recovery bundle and remap every packaged source to byte-identical content in the retained history.
- Do not force-push, rewrite published commits, or rebuild the historical index without explicit authorization.
- Keep commits focused; on shared history, rebase unpublished work onto fetched `origin/main` instead of merging generated index commits. Never rebase a rewritten root onto its pre-rewrite remote history.
- Version actions before index generation. Do not amend a published version to hide changes.
- Deploy serially, validate the checked-out source, and push normally. A concurrent source push should reject a stale index push rather than overwrite it.
- Passing local checks does not authorize publishing.
