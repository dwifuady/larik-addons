# Larik add-ons

The curated index for [Larik SQL Studio](https://github.com/dwifuady/larik-winui) database
**drivers, packaged as add-ons**. The app reads one JSON file from this repository; driver code
lives in the author's own repository and ships as a GitHub Release zip.

- [`official.json`](official.json) — the first-party index used by the Microsoft Store build.
- [`index.json`](index.json) — the open index used by the installer, portable ZIP and winget builds.

Nothing here is installed automatically. An entry only makes an add-on **offerable**; the user
chooses it in the app's Drivers page.

## How it works

```
provider repo ──release zip──▶ index.json ──raw.githubusercontent──▶ app ──▶ LocalAppData
   (source)      (immutable)     (this repo)      (no token)          verify  (restart to load)
```

1. The author publishes `larik.<id>-<version>-win-<arch>.zip` as a GitHub Release asset.
2. A pull request adds one entry to `index.json` with the URL and its SHA-256.
3. CI downloads the zip, verifies the hash, and checks that it contains a matching
   `larik-addon.json` and the declared entry assembly.
4. A maintainer reviews and merges.
5. The app lists the add-on, downloads it on request, verifies the hash again, installs it under
   `%LOCALAPPDATA%\Larik WinUI\Plugins\<id>\<version>\`, and asks for a restart.

## Entry rules

| Rule | Why |
|---|---|
| `url` is an immutable release asset | `releases/latest/download/...` can change under the hash |
| `sha256` is lowercase hex of the exact zip | Verified again on the user's machine |
| `id` is reverse-DNS and never reused | It owns a folder and a saved `provider_id` |
| `providerIds` are unique across the index | Two add-ons cannot answer the same provider id |
| `contract` is `>=x.y <z.w` | The app compares it to `LarikDataContract.Version` before loading |
| The zip carries `LICENSE` and `THIRD-PARTY-NOTICES.md` | A downloaded driver needs its own notices |

## Trust

Add-ons are **trusted, in-process .NET code**. Approval is a review claim, not a sandbox. The index
is hash-pinned today; a detached signature over each entry is required before the open index accepts
third-party entries. Until then, `index.json` should only contain reviewed first-party entries.

## Local validation

```powershell
pwsh ./scripts/validate.ps1 -VerifyDownloads
```

The same command runs in CI. `-VerifyDownloads` needs network access; omit it for a quick offline
syntax check.

## Submitting an add-on

Read [`CONTRIBUTING.md`](CONTRIBUTING.md). The provider contract and packaging guidance are in
[`docs/ADDONS.md`](https://github.com/dwifuady/larik-winui/blob/main/docs/ADDONS.md).

## Files

| Path | Purpose |
|---|---|
| `index.json` | Open channel entries |
| `official.json` | First-party channel entries |
| `schema/index.schema.json` | Editor/tooling schema for both index files |
| `schema/addon-manifest.schema.json` | `larik-addon.json` schema |
| `scripts/validate.ps1` | CI and local validation |
| `.github/workflows/validate.yml` | Pull-request gate |
