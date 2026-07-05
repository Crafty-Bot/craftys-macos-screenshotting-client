# Upload Backends

How CraftyCannon gets your content onto a server: backends, profiles, credential storage, S3 mirroring, endpoint validation, the Cloudflare allowlist, and the URL shortener.

## Backends

`enum UploadBackend` (`Models.swift`) supports two backend types:

- **`ziplineV4`** — targets a [Zipline](https://zipline.diced.sh/) v4 instance, a self-hostable file/image host. This is the default/primary backend.
- **`s3Compatible`** — any S3-compatible object store (AWS S3, MinIO, Cloudflare R2, etc.), uploaded via a hand-rolled AWS SigV4 request signer (`S3Uploader.swift`, using CryptoKit — no AWS SDK dependency).

### Zipline uploads

A streamed multipart/form-data `POST` to `{endpoint}/api/upload`, with the request body written to a temp file first so large images don't need to sit fully in memory. The raw API token is sent as the `Authorization` header (not `Bearer`-prefixed); an `x-zipline-deletes-at` header carries the expiry for expiring uploads. The response is parsed tolerantly — it looks for `url`/`link` either at the top level or inside a `files[0]` array, since Zipline's response shape has varied across versions.

### S3-compatible uploads

The object key is built from a date folder, a random UUID prefix, a sanitized upload-context tag, and the filename (optionally under a configured key prefix). The request is signed with full SigV4 (canonical request + signing key derivation) and sent via `URLSession.upload`. The returned URL is chosen by priority: a signed GET URL (if one was explicitly requested), a `publicBaseURL`-based URL (for CDN/custom domains), a signed GET URL (if your profile defaults to signed URLs), or finally the raw bucket/object URL.

## Profiles

An `UploadProfile` bundles everything needed to reach a destination *except* secrets:

```swift
struct UploadProfile {
  var id: String
  var name: String
  var endpoint: String
  var backend: UploadBackend          // .ziplineV4 or .s3Compatible
  var s3Config: S3DestinationConfig?  // present only for S3 profiles
  var secondaryS3ProfileId: String?   // optional link to a secondary mirror profile
}
```

S3 profiles additionally carry `S3DestinationConfig`: endpoint, region, bucket, key prefix, path-style vs. virtual-hosted-style addressing, an optional public base URL, and signed-GET-URL defaults (including expiry, clamped 60s–7 days).

### Managing profiles

Add, edit, remove, import, and export profiles from the **Preferences window** (status-bar menu → Preferences, or Cmd+,) — this is a dedicated AppKit window separate from the main window's Settings rail. Each profile has its own "Validate" button to test connectivity/credentials before saving.

You can run any number of profiles simultaneously and switch the **active** one, or let CraftyCannon auto-route uploads to a specific profile based on file extension (uploader filters) or content kind — image/file/text/shortener (destination routing) — configured in the main window's Settings.

**Export deliberately excludes secrets** — exported profile bundles have all credential fields nulled out, so sharing/backing up a profile bundle never leaks tokens. Re-importing a bundle restores profile metadata but requires re-entering credentials unless the bundle happened to include them.

### Where credentials live

Never in `UserDefaults` or the exported JSON — always in the macOS **Keychain** (`Keychain.swift`), with each profile's credentials stored under their own distinct Keychain entry. Items use `kSecAttrAccessibleAfterFirstUnlock`, meaning they're readable once the Mac has been unlocked since boot — appropriate for a background app that may need to upload without the user actively present, while still protecting secrets before first unlock.

A legacy single-profile install (pre-multi-profile, v0.1.0) is migrated automatically on first launch of a newer build, preserving its one API key under the new per-profile Keychain storage.

## Secondary S3 mirroring

An **optional** secondary upload that runs alongside (not instead of) a primary Zipline upload — useful for keeping your own backup copy in S3 regardless of what your primary Zipline host does.

- Only Zipline-primary profiles can have a secondary S3 mirror; an S3-primary profile cannot.
- Link a Zipline profile to an S3 profile via `secondaryS3ProfileId`, set from the Preferences profile editor (pick a "secondary S3 mirror" profile while editing a Zipline profile).
- After every successful primary upload, CraftyCannon uploads the **same local file, with the same generated remote filename, the same expiry**, to the linked S3 profile.
- **Zipline's URL is always the canonical one** — it's what gets copied to your clipboard, opened, shortened, and recorded as the upload's primary URL. The S3 mirror's URL is purely auxiliary, stored on the history record's `secondaryURL` field and visible in the History Workspace, but never copied/opened automatically.
- A mirror failure never affects the primary upload — you'll see a "S3 mirror failed" notification and a `secondaryError` on the history record, but your link/clipboard/notification flow proceeds normally.

### AWS CLI credential import

During first-run onboarding, if a Zipline profile is chosen as primary, CraftyCannon checks `~/.aws/credentials` and `~/.aws/config` for existing AWS CLI profiles. If found, it offers to create a linked secondary S3 mirror pre-filled with that profile's region, endpoint, and credentials — you just pick the bucket and key prefix. This is purely a convenience for onboarding; you can set up or change a secondary mirror at any time from Preferences without touching AWS CLI files again.

## Endpoint validation

Both in onboarding and from the Preferences "Validate" button, CraftyCannon checks that a profile is actually reachable before you rely on it:

- **S3 profiles** — performs a real signed `PUT` of a small probe object to the configured bucket, checks for a 2xx response, then best-effort deletes it. Distinguishes "missing config", "missing credentials", and "HTTP failure" in its error messages.
- **Zipline profiles** — sends a `HEAD` request to `{endpoint}/api/upload` and classifies the result: 200–299, 401, 403, 404, and 405 are all treated as "reachable" (a real Zipline server correctly rejects an unauthenticated/wrong-method `HEAD` with one of these codes, which still proves it's a Zipline endpoint). A 404 specifically gets a deliberately generous "Assuming reachable" message, since some reverse-proxy setups 404 on `HEAD` or on `/api/upload` without `POST`.

A historical bug (fixed 2026-06-10, see [docs/UPDATE_NOTES.md](docs/UPDATE_NOTES.md)) caused a reachable backend to be marked failed if the server sent HTTP headers and then closed the connection before the body finished streaming. The classification logic is now a pure function of `(statusCode, body)` where `body` is optional and never required to be non-nil or complete — only the status code matters for the reachability verdict.

## Cloudflare allowlist automation

Solves a specific problem: if your upload destination sits behind Cloudflare with an IP allowlist (e.g. a self-hosted Zipline instance protected by a Cloudflare WAF rule), your Mac's changing public IP (different networks, dynamic ISP address) will periodically lock you out unless something keeps the list updated. `CloudflareAllowlistManager.swift` does that automatically.

**Configuration** (Settings → Cloudflare allowlist):
- Enable/disable
- Cloudflare **account ID**
- **List ID** — either the 32-character hex ID directly, or a human-readable list name (e.g. `crafty`), resolved at runtime by name-matching your account's IP lists
- **Device name** — a label embedded in the list entry so you can tell which Mac owns it
- **Check interval** (5–1440 minutes, default 15)
- **API token**, stored in Keychain, separate from upload-profile credentials

**When it runs**: on the configured interval timer, *and* immediately after a detected network-path change (new Wi-Fi network, waking on a different connection) — debounced 3 seconds to avoid refresh storms during flappy transitions, and only triggered if the new network state actually differs from the last one observed.

**What it does on each run**: resolves the list ID, fetches the Mac's current public IP (via `https://cloudflare.com/cdn-cgi/trace`), fetches the list's current contents, computes a new item set, and replaces the list contents via the Cloudflare API.

**Safeguard**: every entry in the list is preserved except ones whose comment matches *this device's own marker* (a per-install UUID embedded in the entry comment, e.g. `craftycannon-device:<uuid> <deviceName> updated <timestamp>`). Other devices' entries — and anything added manually — are never touched; only this Mac's own managed entry gets replaced.

You can also trigger an update manually from the same Settings panel.

## URL shortener

A standalone utility, not an automatic part of the upload pipeline — nothing uploads through it implicitly. Invoked explicitly, either on an arbitrary URL you type in, or on an existing history record's URL (via its **Shorten** button). Two providers:

- **TinyURL** — a simple `GET` to TinyURL's API.
- **Custom GET template** — any endpoint URL containing a literal `{url}` placeholder; the response is parsed as JSON (`{"url": ...}` or `{"shortUrl": ...}`) or, failing that, as a raw plain-text URL.

On success the shortened URL is copied to the clipboard and a "Shortened URL" notification fires.

## End-to-end upload flow

Tracing a representative path (image capture upload):

1. **Redaction check** (`UploadService.prepareImageForUpload`) — per your `uploadRedactionPolicy` (Off / Ask before upload / Auto-redact), runs Smart Redaction and either uploads the original, redacts automatically, or prompts you (Redact & Upload / Upload Original / Cancel). See [REDACTION.md](REDACTION.md).
2. **Local copy decision** — depending on your After Capture preferences, a local copy may be kept in CraftyCannon's managed image directory and/or mirrored into a dated screenshots folder.
3. **Profile routing** — extension-based uploader filters take priority, then content-kind destination routing, then your active profile.
4. **History record created** as `.uploading` *before* the network call starts, so it shows immediately in the History Workspace; OCR indexing is enqueued at the same time.
5. **Primary upload** runs (Zipline or S3, per the routed profile's backend); the resulting URL passes through any configured URL-rewrite rule.
6. **History updated** to `.uploaded` (with the URL) or `.failed` (with an error message), and a notification fires.
7. **Post-upload tasks** run — copy URL and/or image to the clipboard, optionally open the editor (capture uploads only) — with the [Discord paste-target override](USER_GUIDE.md#discord-paste-behavior) substituting a URL-as-text copy when Discord is frontmost.
8. **Secondary S3 mirror** (if linked) uploads after the primary succeeds, never blocking or affecting the primary result.
9. **Cleanup** — temp/intermediate files (redacted copies, downloaded remote content) are removed if they weren't meant to be kept, with a safety check that only files actually under the system temp directory are ever deleted.

Other entry points (file upload, remote-URL download-then-upload, text upload, folder/folder-index batch upload, re-upload) share this same shape, differing mainly in step 1 (redaction only applies to images) and how the source file is obtained.
