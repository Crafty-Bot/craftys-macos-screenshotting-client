# CraftyCannon Update Notes

## 2026-06-10

- Fixed endpoint validation so a reachable backend is not marked failed when the server closes the response body early after sending HTTP headers.
- Added tests for endpoint validation status handling, including worker responses without readable bodies and Zipline auth responses.

## 2026-06-09

- Cloudflare allowlist updates now also run immediately after network changes (new Wi-Fi, wake on a different connection) instead of waiting for the next interval refresh.
- Added tests for Cloudflare network path refresh decisions.

## 2026-05-29

- Added Cloudflare allowlist automation that keeps this Mac's current public IP in a configured Cloudflare IP list.
- Added a Settings > Cloudflare allowlist panel for account/list IDs, device name, refresh interval, Keychain-backed API token storage, and manual updates.
- Added safeguards so Cloudflare list updates preserve existing entries and replace only this device's managed entry.
- Cloudflare allowlist settings now accept either a list name like `crafty` or the 32-character API list ID.
- Fixed Cloudflare list item pagination to avoid invalid or expired cursor responses.
- Improved upload/watch-folder reliability with safer file handle cleanup, bounded watch-folder dedupe state, and small preference/keychain cleanup fixes.

## 2026-05-14

- When Discord is the active paste target, image upload workflows now copy the uploaded link instead of image data so Discord pastes a URL rather than creating a new attachment.

## 2026-05-13

- Added an OLED Black theme with true black shell and panel backgrounds for OLED displays.
- Added optional secondary S3 mirroring for Zipline profiles.
- Zipline remains the primary upload destination and copied/opened URL; the S3 mirror URL and status are stored in upload history.
- Added first-run Zipline setup support for importing local AWS CLI credentials and creating a linked secondary S3 mirror profile.
- Added history display/search support for secondary S3 mirror URL and error metadata.
- Added tests for OLED palette registration, secondary S3 profile metadata, and secondary upload history metadata.
