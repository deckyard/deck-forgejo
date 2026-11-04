<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/forgejo

A client for the [Forgejo](https://forgejo.org/) REST API, the API of
Codeberg and of self-hosted Forgejo. `call` reaches any endpoint of
`/api/v1` and `getAll` follows the pages of a list. Typed verbs cover the
daily work: repositories and their settings, collaborators and webhooks;
issues, comments, labels and milestones; pull requests, reviews and
merging; releases and their assets; branches, tags and files; commits,
commit statuses and Forgejo Actions (workflows, secrets, variables).

Gitea speaks the same API, so most of the deck works there too; it is tested
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

Every failure is `Error{kind: "forgejo"}`. The message names the request,
the HTTP status and Forgejo's reason:

```text
forgejo: GET /repos/me/missing: HTTP 404: The target couldn't be found.
forgejo: POST /user/repos: HTTP 409: The repository with the same name already exists.
```

## Requirements

Jennifer 0.26.0 or newer, the default `jennifer` binary, and the `net`
capability.
