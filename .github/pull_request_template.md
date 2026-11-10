## What this adds

<!-- One sentence: the engine/engine family and the provider ids. -->

## Checklist

- [ ] One entry per platform in `index.json` (and `official.json` only for first-party add-ons)
- [ ] `url` is an immutable GitHub Release asset, not `latest`
- [ ] `sha256` is the hash of the exact zip
- [ ] `providerIds` are unique across the index
- [ ] `contract` matches the `Larik.Data` version the add-on was built against
- [ ] The zip has `larik-addon.json`, `LICENSE`, and `THIRD-PARTY-NOTICES.md`
- [ ] `pwsh ./scripts/validate.ps1 -VerifyDownloads` passes locally
- [ ] The provider source repository is public
