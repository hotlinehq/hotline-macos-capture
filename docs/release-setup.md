# Release setup (once), then releases by tag

Releases are built, signed, notarized (checked by Apple for malware) and published by `.github/workflows/release.yml` on a GitHub macOS machine. Nothing is built on your own Mac, and you do not need a Mac for this setup: certificate files are made with `openssl`, which is on Linux and Windows too.

**Status: never run.** Apple's website changes, and I wrote these steps without being able to try them. If a step does not match what you see, tell me and I will fix this file.

## 1. Apple Developer Program

Join at developer.apple.com (paid yearly). You must be the Account Holder to make a Developer ID certificate. Note your **Team ID** (Membership details page): 10 letters and digits.

## 2. Developer ID certificate (without a Mac)

```
openssl genrsa -out dev-id.key 2048
openssl req -new -key dev-id.key -out dev-id.csr -subj "/emailAddress=YOUR_EMAIL/CN=YOUR_NAME/C=CZ"
```

On the Apple developer site: Certificates, Identifiers & Profiles, Certificates, add one, type **Developer ID Application**, upload `dev-id.csr`, download the `.cer` file. Then:

```
openssl x509 -inform DER -in developerID_application.cer -out cert.pem
openssl pkcs12 -export -legacy -inkey dev-id.key -in cert.pem -out dev-id.p12
```

Choose an export password and remember it. (`-legacy` is needed with OpenSSL 3 so that macOS can read the file; drop it if your OpenSSL says it does not know the flag.) Keep `dev-id.key` and `dev-id.p12` private; never commit them.

## 3. Two app identifiers

Identifiers, add an **App ID** twice:

| Identifier | Capabilities |
| --- | --- |
| `io.github.petercipov.hotlinecapture` | System Extension, Network Extensions |
| `io.github.petercipov.hotlinecapture.extension` | Network Extensions |

Apple may review the Network Extensions permission before it is granted. Not verified. If you want other identifiers, change them in `project.yml`, `scripts/build-release.sh` and the two `Logger` and `extensionIdentifier` names in `App/` and `Extension/`.

## 4. Two provisioning profiles

Profiles, add one per identifier, type **Developer ID**, using the certificate from step 2. Name them exactly:

- `Hotline Capture` (for the app)
- `Hotline Capture Extension` (for the extension)

Download both `.provisionprofile` files.

## 5. App-specific password for notarizing

At appleid.apple.com, Sign-In and Security, App-Specific Passwords, make one named `hotline-capture-notary`.

## 6. GitHub secrets

In the repository: Settings, Secrets and variables, Actions, New repository secret. Make these seven. `base64 -w0 FILE` on Linux, `base64 -i FILE` on a Mac:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | base64 of `dev-id.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | the export password from step 2 |
| `APPLE_PROVISIONING_PROFILE_APP` | base64 of the `Hotline Capture` profile |
| `APPLE_PROVISIONING_PROFILE_EXT` | base64 of the `Hotline Capture Extension` profile |
| `APPLE_ID` | your Apple id email |
| `APPLE_APP_PASSWORD` | the app-specific password from step 5 |
| `APPLE_TEAM_ID` | your Team ID from step 1 |

The release workflow checks that all seven exist and names any that are missing. Secrets are not passed to pull requests from forks, and the workflow starts on tags only.

## 7. Make a release

```
git tag v0.1.0
git push origin v0.1.0
```

The tag number becomes the app version. The build number is the run number, so it always rises, which the extension needs. When the run ends, the GitHub release holds `HotlineCapture.app.tar` and `HotlineCapture.app.tar.sha256`.

## 8. Check a release

Download both files, then `shasum -a 256 -c HotlineCapture.app.tar.sha256`. The Hotline Go release downloads one fixed version of the tar, checks this checksum and embeds it.

## If something fails

- **A secret is missing:** the first step says which one.
- **Certificate not found or cannot be read:** redo the p12 export of step 2.
- **Profile does not match:** the profile names or identifiers differ from steps 3 and 4.
- **Notarization refused:** the run log shows Apple's reason; send it to me.
