---
description: Cut a Birchboard release — bump versions, push tag, monitor workflow, verify appcast.
argument-hint: "[patch|minor|major|X.Y.Z]   (default: patch)"
---

You are cutting a new Birchboard release. The full per-release procedure is documented in `RELEASE_PROCESS.md` at the repo root — re-read it if anything below is unclear. This command automates steps 1–3 of that doc plus monitoring and verification.

User argument: `$ARGUMENTS`

## Preflight (abort if any check fails — do not "fix" by force)

1. CWD must be the repo root (`/Users/birch/dev/clipboard-manager`).
2. Current branch must be `main` and up to date with `origin/main`.
3. Working tree must be clean. If there are uncommitted changes, **stop** and tell the user — they need to commit or stash first. Releases are version-bump-only commits.
4. `gh auth status` must succeed.

## 1. Compute the next version

Read the current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `Birchboard/project.yml` (single source of truth — they are referenced by the Info.plist and by the release workflow).

Resolve `$ARGUMENTS`:

- empty or `patch` → bump the third component of `MARKETING_VERSION` (e.g. `0.2.1` → `0.2.2`)
- `minor` → bump the second component, reset patch to 0 (e.g. `0.2.1` → `0.3.0`)
- `major` → bump the first component, reset minor and patch (e.g. `0.2.1` → `1.0.0`)
- looks like `X.Y.Z` → use exactly that string

`CURRENT_PROJECT_VERSION` always increments by exactly 1 (it's `CFBundleVersion`, and Sparkle's default comparator matches it as an integer against the appcast's `<sparkle:version>` — skipping a bump or feeding a non-integer makes installed clients think they're already on the latest).

State the resolved versions back to the user before proceeding (e.g. "Bumping 0.2.1 → 0.2.2, build 3 → 4").

## 1.5 Preview release notes (and offer override)

Sparkle's "Update Available" dialog renders the appcast `<description>` as HTML. The release workflow auto-derives that content from the commit log between the previous tag and this one, filtered to drop the `Bump to X.Y.Z` and `Update appcast` housekeeping commits. Show the user a preview so they can confirm it reads well.

```sh
LATEST_TAG=$(git describe --tags --abbrev=0)
git log --no-merges --pretty='format:- %s' "$LATEST_TAG..HEAD" \
    | grep -vE '^- Bump to |^- Update appcast'
```

If the preview is empty (rare — happens when every commit since the last tag is housekeeping), warn the user and confirm they really want to release; the workflow's fallback is "Maintenance release." which is fine but should be a deliberate choice.

Then ask: **keep the auto-derived notes, or write a custom override?**

- **Auto-derived (default)** — do nothing extra. The workflow will format the bullets above as `<ul><li>…</li></ul>` and embed them in the appcast.
- **Override** — drop a hand-written HTML file at `docs/release-notes/<MARKETING_VERSION>.html` (no `v` prefix; e.g. `docs/release-notes/0.3.0.html`). The workflow uses it verbatim. Useful when the bullets need a sentence of context, a link, or grouping into "New" / "Fixes" sections.

If the user picks override, write the file. Pre-populate it with the auto-derived bullets converted to HTML so they have a starting point. A sensible structure is:

```html
<p>Headline of the release in a sentence.</p>
<ul>
    <li><strong>Feature name</strong> — what it does and why it's useful.</li>
    <li>Smaller fix or polish item.</li>
</ul>
```

The override file gets staged alongside `Birchboard/project.yml` in step 2's commit so the workflow sees it at the tagged ref.

## 2. Edit, commit, push

Edit `Birchboard/project.yml`, replacing both fields. Stage `project.yml` (and the `docs/release-notes/<MARKETING_VERSION>.html` override, if step 1.5 produced one):

```sh
git add Birchboard/project.yml
# Plus, if a release-notes override was authored in step 1.5:
git add docs/release-notes/X.Y.Z.html
git commit -m "Bump to X.Y.Z"
git push origin main
```

The commit must contain **only** the version bump and (optionally) the matching release-notes override — nothing else. If `git status` after the edit shows any other modified file, abort and ask the user.

## 3. Annotated tag + push

```sh
git tag -a vX.Y.Z -m "Birchboard X.Y.Z"
git push origin vX.Y.Z
```

Annotated (`-a`), not lightweight — `softprops/action-gh-release` reads the annotation for default release notes.

## 4. Monitor the Release workflow

Find the run triggered by the tag push (it should appear within ~5s):

```sh
gh run list --workflow=release.yml --limit 1
```

Confirm the row's `headBranch` is `vX.Y.Z`, then watch it:

```sh
gh run watch <run-id> --exit-status
```

The watch can take 4–12 minutes (notarization queue). Use a generous Bash `timeout` (≥ 900000 ms / 15 min). On completion, verify success with:

```sh
gh run view <run-id> --json status,conclusion --jq '{status, conclusion}'
```

If `conclusion` is not `success`, fetch the failed step's log and surface the relevant error to the user — do not retry automatically. Common causes are documented under "Troubleshooting" in `RELEASE_PROCESS.md`.

## 5. Verify the appcast

The workflow commits an updated `docs/appcast.xml` back to `main`. Pull and inspect:

```sh
git fetch origin main && git pull --ff-only origin main
```

Confirm the new `<item>` is present in `docs/appcast.xml`:

- `<sparkle:version>` matches the new build integer
- `<sparkle:shortVersionString>` matches the new marketing version
- An `enclosure` `url` points at `https://github.com/birchsport/clipboard-manager/releases/download/vX.Y.Z/Birchboard-X.Y.Z.dmg`
- An `sparkle:edSignature` attribute is present (non-empty)

Then verify the **published Pages copy** has caught up (Pages takes ~30–60s after the commit):

```sh
curl -s https://birchsport.github.io/clipboard-manager/appcast.xml \
  | grep -E "(Version X\.Y\.Z|sparkle:version>NEW_BUILD<)"
```

Both lines should appear. If only the local `docs/appcast.xml` has the entry but the Pages copy doesn't, wait 30s and re-curl once before reporting — don't poll forever.

## 6. Final summary to the user

Report:

- the two SHAs (the bump commit + the appcast commit pushed back by the workflow)
- the tag and Release URL (`https://github.com/birchsport/clipboard-manager/releases/tag/vX.Y.Z`)
- DMG filename + size from `gh release view`
- Confirmation that both the repo and Pages appcasts contain the new entry

Existing installs ≥ 0.2.0 will pick the update up via Sparkle within 24h, or immediately via Settings → General → Check Now.

## Things to NOT do

- Do not skip hooks, force-push, or delete tags to "fix" a stuck release. If the workflow fails, surface the error and stop.
- Do not commit anything other than the version bump in step 2.
- Do not edit `docs/appcast.xml` by hand — the workflow owns it.
- Do not retry a failed workflow without the user's say-so.
