# Signing

GearMac is signed with **two identities, one per audience**:

- **Local development builds** (Xcode, `xcodebuild`, the copy in `/Applications`) use the Apple
  **Developer ID Application** certificate. Its Team ID is what macOS anchors *stable* grants to:
  the login-keychain ACL records `certificate leaf[subject.OU] = <Team ID>` — an expression that
  survives every rebuild. A self-signed identity carries no Team ID, so the keychain falls back to
  recording the build's cdhash: every rebuild prompted "enter your login keychain password" before
  the app could read its own API keys (see `.context/research/keychain-prompt-root-cause.md`). The
  same Team ID anchoring keeps the Accessibility (TCC) grant stable across rebuilds, which was the
  original reason a *stable* self-signed identity was introduced — Developer ID does that strictly
  better.
- **CI releases** sign with the same **Developer ID Application** certificate (imported from GitHub
  secrets) and are **notarized** with `xcrun notarytool`, so a directly-downloaded DMG opens without a
  Gatekeeper warning. The migration from `GearMac Self-Signed` is complete — see
  [The Developer ID migration](#the-developer-id-migration).

You create each identity **once**:

## 1. Local identity (once)

The Xcode project signs with whatever Developer ID Application certificate is in your login
keychain (set in `project.yml` → `CODE_SIGN_IDENTITY`). Verify it is present:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

If codesign asks once for the keychain password to use the private key, approve "Always Allow" —
like everything else anchored to the Team ID, that prompt happens once, ever.

## 2. Create the `GearMac Self-Signed` identity (once — legacy)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=GearMac Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "GearMac Self-Signed" -out /tmp/tc.p12 -passout pass:gearmac

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P gearmac -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "GearMac Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

## 3. Generate the CI secrets

The release workflow needs the Developer ID identity and the notary credentials as repo secrets.
Export the identity (approve the keychain dialog if asked), base64-encode it, and pick a password:

```sh
# Pick a random password for the exported bundle.
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"

# Export the identity (approve the keychain dialog if asked) and base64-encode it.
security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" -o /tmp/signing.p12
base64 -i /tmp/signing.p12 | tr -d '\n' > /tmp/signing.p12.base64
rm -f /tmp/signing.p12
```

Then set the two secrets on the repo (via `gh`, authed as the repo owner, or paste them in the GitHub
UI under **Settings → Secrets and variables → Actions**):

```sh
gh secret set SIGNING_P12_BASE64   --repo GearMac/GearMac < /tmp/signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo GearMac/GearMac --body "$P12_PASSWORD"
rm -f /tmp/signing.p12.base64   # holds your private key — delete it
```

Notarization authenticates with an App Store Connect API key (Users and Access → Integrations →
App Store Connect API). Download the `.p8` once and set three more secrets:

```sh
base64 -i AuthKey_<KEYID>.p8 | tr -d '\n' > /tmp/api.b64
gh secret set APPLE_API_KEY_CONTENT --repo GearMac/GearMac < /tmp/api.b64
gh secret set APPLE_API_KEY_ID     --repo GearMac/GearMac --body "<KEYID>"
gh secret set APPLE_API_ISSUER_ID  --repo GearMac/GearMac --body "<ISSUER-UUID>"
rm -f /tmp/api.b64 AuthKey_<KEYID>.p8
```

If you ever lose the secrets, just re-run this section — as long as the `GearMac Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 2) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`, which notarization requires. Debug
must stay without it — hardened runtime turns on library validation, and Xcode's
`GearMac-dev.debug.dylib` is refused at launch because a self-signed identity carries no Team ID for
the loader to match. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Each entitlement in `GearMac//GearMac.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` returns `false` in milliseconds with no dialog, and GearMac never appears under System Settings › Calendars |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources GearMac does not use. That grants nothing — only
`GearMac.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. Both release jobs run it before packaging:
a nested binary missing the runtime flag is the most common notarization rejection, and a usage string
missing its entitlement ships a permission that can never be granted.

## The Developer ID migration

`BundleSignature` accepts a bundle signed by the GearMac team under Apple's Developer ID chain, and
since the CI switch it also accepts the running app's own leaf — the only thing a copy installed
before the migration knows how to check. Releases are now signed `Developer ID Application`, so a
copy that predates the switch updates once through its own-leaf branch and thereafter verifies the
chain like everyone else.

The requirement pins the team rather than the certificate, so a Developer ID renewal strands nobody.
It deliberately omits the `notarized` keyword — that resolves a ticket through `syspolicyd` or the
network, and the updater verifies in a cache directory Gatekeeper has never assessed, so an offline
Mac would refuse a bundle the chain already proves is ours.

**Both local builds and CI releases sign with the same `Developer ID Application` identity, and CI
output is notarized and stapled.** `project.yml` signs local builds with the Developer ID
certificate so keychain and TCC grants anchor to the Team ID; contributors without that certificate
can override `CODE_SIGN_IDENTITY` on the command line with a self-signed identity of their own —
they will re-grant Accessibility and keychain access once per rebuild (the cdhash behaviour above),
which is the trade macOS gives identities without a Team ID.

**Keep `GearMac Self-Signed` in the login keychain after the switch.** It is the only way to ship a
build that a copy predating the migration could still install.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
