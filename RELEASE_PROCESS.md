# Release process

Cutting a new Birchboard release is a two-file edit plus a tag push.
GitHub Actions handles everything else: signed + notarized DMG, EdDSA
update signature, appcast append, GitHub Release publish.

## Prerequisites (one-time)

The `Release` workflow needs seven repo secrets (Settings → Secrets and
variables → Actions):

| Secret                        | Value                                                    |
| ----------------------------- | -------------------------------------------------------- |
| `DEVELOPER_ID_P12_BASE64`     | `base64 -i developer_id.p12` of the exported cert        |
| `DEVELOPER_ID_P12_PASSWORD`   | password you chose when exporting the .p12               |
| `KEYCHAIN_PASSWORD`           | any random string (used for the ephemeral keychain)      |
| `APPLE_ID`                    | Apple ID email associated with the Developer account     |
| `APPLE_TEAM_ID`               | 10-char team id (mine: `4Q4VFU52B6`)                     |
| `APPLE_APP_PASSWORD`          | app-specific password from appleid.apple.com             |
| `SPARKLE_ED_PRIVATE_KEY`      | `generate_keys -x` output from Sparkle's tools bundle    |

And Settings → Actions → General → Workflow permissions → **Read and
write** (so the workflow can commit the updated `docs/appcast.xml`
back to `main`).

## Per-release steps

1. **Bump the version** in `Birchboard/project.yml`:

    ```yaml
    MARKETING_VERSION: "0.3.0"        # the human-readable version
    CURRENT_PROJECT_VERSION: "4"      # CFBundleVersion — integer, must
                                      # strictly increase every release
    ```

    The integer matters. Sparkle's default comparator matches the
    appcast's `<sparkle:version>` against the installed
    `CFBundleVersion`, not the marketing string. Skip the bump and
    installed clients will think they're already on the latest.

2. **Commit on `main`**:

    ```sh
    git add Birchboard/project.yml
    git commit -m "Bump to 0.3.0"
    git push origin main
    ```

3. **Tag and push**:

    ```sh
    git tag -a v0.3.0 -m "Birchboard 0.3.0"
    git push origin v0.3.0
    ```

    Use annotated tags (`-a`), not lightweight —
    `softprops/action-gh-release` reads the annotation for default
    release notes when `generate_release_notes` doesn't produce any.

That's it. The workflow fires on the tag push and takes 4–12 minutes
depending on notarization queue time.

## What the workflow does

1. Imports the Developer ID cert into an ephemeral keychain.
2. Runs `scripts/make-dmg.sh` — archives the Release config, re-signs
   Sparkle's nested XPC services + helpers, notarizes the DMG with
   `xcrun notarytool --wait`, staples the ticket.
3. Signs the DMG with `sign_update` (Sparkle's EdDSA private key).
4. Appends an `<item>` to `docs/appcast.xml` — idempotent; if an entry
   for this `<sparkle:version>` already exists, it's replaced.
5. Commits the appcast back to `main`.
6. Publishes a GitHub Release with the DMG attached.

## Verifying

After the workflow shows green:

- **Release page** — the `Birchboard-$VERSION.dmg` asset is attached at
  `https://github.com/birchsport/clipboard-manager/releases/tag/vX.Y.Z`.
- **Appcast** — `curl -s https://birchsport.github.io/clipboard-manager/appcast.xml`
  should show a new `<item>` for this version. Pages takes ~30–60s to
  pick up the commit.
- **End-to-end** — on a previously-installed build (≥ 0.2.0, when
  Sparkle was wired in), open Settings → General → Check Now. You
  should get an update prompt within a few seconds.

## Troubleshooting

- **Re-running a workflow**: the appcast step is idempotent by
  `<sparkle:version>`, so re-runs are safe.
- **Re-pushing a tag doesn't trigger a new run**: GitHub suppresses the
  push event when you delete+recreate a tag too quickly. Use
  Actions → Release → Run workflow and pass the tag as input, or
  wait a few minutes and push again.
- **Notarization failed**: the workflow's `Dump notarization log on
  failure` step extracts the submission id from the log and fetches
  the human-readable error. Common causes:
  - Developer ID cert expired or revoked — regenerate and update
    `DEVELOPER_ID_P12_BASE64` / `DEVELOPER_ID_P12_PASSWORD`.
  - Hardened runtime disabled — `ENABLE_HARDENED_RUNTIME: YES` must
    be set in `project.yml` (it is).
  - Nested Sparkle binaries not re-signed — `make-dmg.sh` handles
    this, but if you add another XCFramework dependency with
    pre-signed binaries, extend the re-sign block.
- **Tag pointed at the wrong commit** (before the release is
  published): `git tag -d vX.Y.Z`, `git push origin :refs/tags/vX.Y.Z`,
  retag on the right commit, push. Safe only if no GitHub Release
  exists yet.
- **Sparkle says "up to date" on an installed older build**: check
  that the appcast's `<sparkle:version>` is the integer build
  number and not the marketing string. The workflow derives this
  from `CURRENT_PROJECT_VERSION` in `project.yml`.

## Rolling a manual release

For a hotfix on an emergency branch or otherwise disabling CI:

```sh
cd Birchboard
NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh
```

Then `sign_update Birchboard/build/Birchboard.dmg -f <keyfile>` to get
the EdDSA signature, hand-edit `docs/appcast.xml`, `gh release create`
with the DMG. See the "Distributing to other Macs" section in
`README.md` for the local notarization setup.
