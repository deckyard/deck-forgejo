# @deckyard/forgejo

[![test](https://github.com/deckyard/deck-forgejo/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-forgejo/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-forgejo/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-forgejo)](https://github.com/deckyard/deck-forgejo/releases/latest)

A client for the Forgejo REST API, for
[Jennifer](https://jennifer-lang.dev/) programs: Codeberg or a self-hosted
Forgejo. Repositories with their settings, collaborators and webhooks;
issues, comments, labels and milestones; pull requests, reviews and
merging; releases with their assets; branches, tags and files; commits,
commit statuses and Forgejo Actions. `call` and `getAll` reach every other
endpoint. Gitea speaks most of the same API.

**[Documentation](https://deckyard.github.io/deck-forgejo/)**

## Install

```sh
jvc add @deckyard/forgejo
```

This vendors the deck to `vendor/<scope>/forgejo/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-forgejo-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/forgejo/" as forgejo;

def c as forgejo.Client init forgejo.client("codeberg.org");
$c = forgejo.withToken($c, fs.readString("/run/secrets/forgejo"));

for (def i in forgejo.issues($c, "me/app", "open")) {
    io.printf("#%d %s\n", $i.number, $i.title);
}
def rel as forgejo.Release init forgejo.createRelease($c, "me/app", "1.2.0", "", "", "Notes", false);
forgejo.uploadAsset($c, "me/app", $rel.id, "app.tar.gz", fs.readBytes("dist/app.tar.gz"));
```

## Requirements

Jennifer 0.26.0 or newer, the default `jennifer` binary (not
`jennifer-tiny`), and the `net` capability.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/forgejo_test.j     # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
