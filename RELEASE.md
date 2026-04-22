# Releasing a signed + notarized DMG

What this gets you: a `.dmg` you can send to a friend on any Mac — they
double-click, drag to Applications, and macOS opens it without warning. No
Gatekeeper block, no "unidentified developer" scare screen.

You do this dance **once per release**. The one-time setup (§1–§3) only
happens once ever.

## Prerequisites

- Active Apple Developer Program membership ($99/yr). You already have one
  (Team ID `4Q4VFU52B6`).
- Xcode installed (you already have 26.x).
- `xcodegen` and `brew` installed (already done).

---

## 1. One-time: get a Developer ID Application certificate

The "Apple Development" cert in `Config/Signing.xcconfig` is for *running
locally*. Distribution needs a different cert type — "Developer ID
Application" — which Gatekeeper trusts on every Mac, not just yours.

1. Go to
   [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list).
2. Click the blue `+` to create a new certificate.
3. Under **Software**, pick **Developer ID Application**. Click Continue.
4. On the next page you need a Certificate Signing Request (CSR). If you
   don't already have one:
   - Open **Keychain Access → Certificate Assistant → Request a Certificate
     From a Certificate Authority…**
   - Enter your email, Common Name (e.g. "James Birchfield - Developer ID"),
     leave CA blank.
   - Select **Saved to disk**, click Continue, save the `.certSigningRequest`
     file somewhere.
5. Back in the browser, upload that CSR. Click Continue.
6. Download the `developerID_application.cer` Apple produces.
7. Double-click it. Keychain Access opens and imports it into your **login**
   keychain.
8. Verify it's there and recognized for code signing:
   ```sh
   security find-identity -v -p codesigning
   ```
   You should see a line like:
   ```
   1) 1234ABCD…  "Developer ID Application: James Birchfield (4Q4VFU52B6)"
   ```

> If `find-identity` lists the cert but says "CSSMERR_TP_NOT_TRUSTED" or
> similar, you may also need to install Apple's **Developer ID
> Intermediate** and **Developer ID Root** certificates from
> [apple.com/certificateauthority/](https://www.apple.com/certificateauthority/).
> Normally Xcode or `security` installs them automatically.

## 2. One-time: generate an app-specific password

`xcrun notarytool` talks to Apple's notary service as you, but using your
normal Apple ID password is blocked for automation. You give it a
throwaway app-specific password instead.

1. Sign in at [appleid.apple.com](https://appleid.apple.com).
2. Go to **Sign-In and Security → App-Specific Passwords**.
3. Click **+ Generate an app-specific password**.
4. Label it something like `Birchboard notarytool`. Click Create.
5. Copy the password **now** — it's shown once, format `xxxx-xxxx-xxxx-xxxx`.

## 3. One-time: store notarization credentials in the keychain

Tell `notarytool` about your Apple ID, Team ID, and the app-specific
password you just generated. It'll store them in your login keychain
under a profile name you pick.

```sh
xcrun notarytool store-credentials "notarytool-birchboard" \
    --apple-id "YOUR_APPLE_ID_EMAIL" \
    --team-id  "4Q4VFU52B6" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

Replace the email and password. `notarytool-birchboard` is just a local label —
you can pick anything; `make-dmg.sh` reads it from `$NOTARY_PROFILE`.

Quick verification:
```sh
xcrun notarytool history --keychain-profile "notarytool-birchboard"
```
Empty history is fine — it just confirms the credentials work.

---

## 4. Build, sign, notarize, and staple the DMG

After the one-time setup, shipping a new build is:

```sh
cd Birchboard
NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh
```

What the script does:

1. `xcodegen generate` — regenerates the Xcode project from `project.yml`.
2. `xcodebuild archive` — builds a Release `.app`. Because the Release
   config overrides `CODE_SIGN_IDENTITY` to `Developer ID Application`, it
   signs with your Developer ID cert + the hardened runtime entitlement
   that's already in `project.yml`.
3. `hdiutil create` — packages the `.app` plus an `Applications` symlink
   into `build/Birchboard.dmg`.
4. `codesign` — signs the DMG itself. Gatekeeper wants both the app and
   the container signed.
5. `xcrun notarytool submit … --wait` — uploads the DMG to Apple's
   servers. Apple scans it for malware, checks the signature, and returns
   a ticket. This takes anywhere from 30 seconds to a few minutes — the
   `--wait` flag blocks until it finishes.
6. `xcrun stapler staple` — attaches the notarization ticket to the DMG
   so it passes Gatekeeper even when the user is offline.
7. `spctl --assess` — prints whether Gatekeeper accepts the final DMG.

Output: `Birchboard/build/Birchboard.dmg`, roughly 3 MB.

### What the notarization output looks like

On success:
```
Processing complete
  id: 1a2b3c4d-5678-…
  status: Accepted
```

On failure you'll get `status: Invalid` and a submission ID. Fetch the log:
```sh
xcrun notarytool log 1a2b3c4d-5678-… \
    --keychain-profile "notarytool-birchboard"
```
Common causes:
- **"The binary is not signed with a valid Developer ID certificate."** —
  you signed with Apple Development. Make sure `project.yml` has the
  Release override and `find-identity` shows a Developer ID Application
  cert.
- **"The executable does not have the hardened runtime enabled."** —
  `ENABLE_HARDENED_RUNTIME` must be YES in build settings. It already is
  in `project.yml`.
- **"The signature of the binary is invalid."** — usually a stale archive.
  Delete `build/` and rerun.

---

## 5. Send it to a friend

Just share `Birchboard/build/Birchboard.dmg`. Your friend:

1. Double-clicks the DMG.
2. Drags Birchboard to Applications.
3. First launch: macOS shows a "downloaded from the internet" prompt — they
   click Open. No scary "unidentified developer" dialog because it's
   notarized.
4. macOS asks for Accessibility permission the first time they ⌘V into
   another app (required to post ⌘V).

---

## 6. When you release a new version

1. Bump `MARKETING_VERSION` in `project.yml` (`0.1.0` → `0.2.0`).
2. Bump `CURRENT_PROJECT_VERSION` (`1` → `2`).
3. Run the same command:
   ```sh
   NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh
   ```
4. Share the new DMG.

The first three sections never need to be redone — Developer ID certs are
good for years, and the keychain profile persists.

---

## Troubleshooting

**"Signing for Birchboard requires a development team."**
Xcode couldn't find a Developer ID Application cert. Check
`security find-identity -v -p codesigning` and re-download the cert from
developer.apple.com if missing.

**"The Developer ID Application certificate expires in N days."**
Certs last ~5 years. Renew via the same flow as §1 when it gets close.

**"CODE_SIGNING_ALLOWED=NO" in Release config**
You're building with `CODE_SIGN_IDENTITY = "-"` somewhere. The xcconfig
in `Config/Signing.xcconfig` shouldn't have `-` — check that it's
`Apple Development`. The Release override in `project.yml` then picks
`Developer ID Application` on top.

**Notarization says "In Progress" forever**
Rare but happens during Apple's outages. Re-submit after 10 minutes. The
`--wait` flag poll-loops with a reasonable backoff.

**Friend's Mac still says "can't be opened"**
Usually means the staple step failed silently. Verify:
```sh
xcrun stapler validate build/Birchboard.dmg
spctl --assess --type open \
    --context context:primary-signature --verbose build/Birchboard.dmg
```
`spctl` should say `accepted source=Notarized Developer ID`. If not,
re-run the full build — stapling has to happen *after* the notary
service accepts the submission.

**Apple ID has two-factor authentication required for App Store Connect**
`notarytool store-credentials` handles this — the app-specific password
from §2 bypasses the 2FA prompt. If you rotated the password, re-run §3
with the new one.
