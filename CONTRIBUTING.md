# Submitting an add-on

## Before you open a pull request

1. **Publish the zip.** Build `Larik.Data.<Engine>` against the published `Larik.Data` package,
   publish for `win-x64` and `win-arm64` separately, and attach each zip to a GitHub Release.
   The zip layout is defined in
   [`docs/ADDONS.md`](https://github.com/dwifuady/larik-winui/blob/main/docs/ADDONS.md).
2. **Include the metadata.** `larik-addon.json`, `LICENSE` and `THIRD-PARTY-NOTICES.md` at the zip
   root, next to the provider DLL and its dependencies.
3. **Compute the hash.**
   ```powershell
   (Get-FileHash .\larik.mysql-1.0.0-win-x64.zip -Algorithm SHA256).Hash.ToLowerInvariant()
   ```
4. **Add one entry** to `index.json`:
   ```json
   {
     "id": "larik.mysql",
     "name": "MySQL",
     "publisher": "your-name",
     "summary": "MySQL provider for Larik SQL Studio.",
     "version": "1.0.0",
     "contract": ">=1.0 <2.0",
     "minAppVersion": "0.4.0",
     "platforms": ["win-x64", "win-arm64"],
     "providerIds": ["mysql"],
     "url": "https://github.com/you/larik-mysql/releases/download/v1.0.0/larik.mysql-1.0.0-win-x64.zip",
     "sha256": "…",
     "sizeBytes": 1234567,
     "license": "MIT",
     "homepage": "https://github.com/you/larik-mysql"
   }
   ```
   One entry per platform, or one entry with both platforms in the array if the zip is universal.
5. **Run the validator.**
   ```powershell
   pwsh ./scripts/validate.ps1 -VerifyDownloads
   ```

## What review looks for

- The provider implements `IDatabaseProvider` and nothing else at startup.
- Credentials come from `ProviderSetting` values; nothing is persisted by the add-on.
- `EffectiveMaxRows` is honoured and results are truncated with `IsTruncated`/`RowLimit`.
- The source repository is public and the licence is compatible with redistribution.
- `THIRD-PARTY-NOTICES.md` covers every bundled dependency.
- No install scripts, no process launching, no network traffic outside the database protocol.

## After merge

Bump the entry with a new version and a new URL for every release. Never edit or reuse an existing
`id + version`; the app treats it as immutable.
