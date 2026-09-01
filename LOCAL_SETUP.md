# OpenScout local setup

This branch is pinned to upstream commit
`3778042d417811dbbc94cd7aa8784858bbc47429` and is intended for one local
Apple-silicon Mac. It does not claim to be an upstream release.

The local hardening changes:

- pin the public Hugging Face model revision and verify every downloaded byte;
- install all 36 voices advertised by the app;
- pin Swift dependency requirements;
- commit separate SwiftPM and Xcode resolution files and require Xcode to use
  the pinned graph;
- vendor MisakiSwift 1.0.4 and link Kokoro/Misaki statically so only one MLX
  runtime is loaded;
- avoid embedding a second copy of the 327 MB model in the package resource bundle;
- build into a per-run directory under `~/Library/Caches/codex-builds`;
- validate the exact app, extension, models, and voice count;
- ad-hoc sign the Audio Unit extension with the App Sandbox entitlement that
  PluginKit requires;
- use a distinct OpenScout bundle and Audio Unit identity;
- ad-hoc sign the local app and fail closed if macOS registration fails;
- never strip Gatekeeper quarantine attributes.

Build and install:

```bash
./scripts/download-models.sh
swift package resolve
swift test
./scripts/build-release.sh
cd dist
./install.sh
```

After installation, launch `KokoroVoice.app`, relaunch OpenScout, then select
`On Device · System voice` and a Kokoro voice in OpenScout Settings → Voice.

The ad-hoc signature is suitable only for this local machine. Distribution
requires a real Apple signing identity, provisioning, notarization, complete
third-party notices, and an upstream-quality review.
