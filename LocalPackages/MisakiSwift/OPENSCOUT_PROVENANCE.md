# Local MisakiSwift package

This directory is a source snapshot of
[`mlalma/MisakiSwift`](https://github.com/mlalma/MisakiSwift) tag `1.0.4`,
commit `dd594b87dcf7b2a9915be09ca44d38172e7c9dab`.

The package manifest is deliberately patched to make the `MisakiSwift`
product static and to pin its MLX dependencies exactly. The adjacent local
KokoroSwift manifest is also static. Upstream publishes both as dynamic
libraries, so each embeds MLX's static Objective-C classes; the client then
embeds another copy of their shared static graph. macOS reports duplicate
class definitions and warns that type casts can fail unpredictably. A single
static linkage unit lets the final extension coalesce the dependency graph.

The source remains under its upstream MIT license in `LICENSE`.
