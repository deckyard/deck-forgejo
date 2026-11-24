<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/forgejo

A client for the [Forgejo™](https://forgejo.org/) REST API, the API of
Codeberg™ and of self-hosted Forgejo. `call` reaches any endpoint of
`/api/v1` and `getAll` follows the pages of a list. Typed verbs cover the
daily work: repositories and their settings, collaborators and webhooks;
issues, comments, labels and milestones; pull requests, reviews and
merging; releases and their assets; branches, tags and files; commits,
commit statuses and Forgejo Actions (workflows, secrets, variables).

Gitea™ speaks the same API, so most of the deck works there too; it is tested
against Forgejo.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/forgejo/" as forgejo;

def c as forgejo.Client init forgejo.client("codeberg.org");
$c = forgejo.withToken($c, fs.readString("/run/secrets/forgejo"));
io.printf("%s\n", forgejo.currentUser($c).login);
```

A `Client` is a value. `withToken` and the other `with*` functions return a
changed copy, so assign the result back to `$c`.

A repository is named `owner/name`: `"forgejo/forgejo"`. Times are the RFC
3339 strings Forgejo sends.

## Errors

Every failure is a `forgejo.ForgejoError` (kind `"forgejo"`). The message names
the request, the HTTP status and Forgejo's reason, and the status is the
`status` field, so a handler branches on it rather than on the text:

```text
forgejo: GET /repos/me/missing: HTTP 404: The target couldn't be found.
forgejo: POST /user/repos: HTTP 409: The repository with the same name already exists.
```

```jennifer
try {
    def r as forgejo.Repository init forgejo.repository($c, "me/missing");
} catch (e) {
    if ($e.kind == "forgejo" and $e.status == 404) {
        io.printf("no such repository\n");
    } else {
        throw $e;
    }
}
```

A list past `MAX_PAGES` pages, a reply over its size cap or nested past the
JSON decoder's caps, or a download past five redirects, is kind `"limit"`
instead, a deadline is kind `"timeout"`, and a connection closed under a
request is kind `"closed"` (each a plain `Error`). A network failure (refused,
reset, unreachable, a name that does not resolve, a failed TLS handshake) is
kind `"net"`: the `net.NetError` that `http` threw, passed on unchanged, so
`reason`, `op`, `sent` and `replied` can be read once the kind matches.

## Requirements

Jennifer 0.27.0 or newer, the default `jennifer` binary, and the `net`
capability.

## Trademarks

Codeberg™ is a trademark of Codeberg e.V. Other product and company names,
such as Forgejo™ and Gitea™, may be trademarks of their respective owners.
They are used only to identify the products this deck works with. This deck
is an independent project, not affiliated with, sponsored or endorsed by
Codeberg e.V., the Forgejo project or CommitGo, Inc.
