<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Repositories

## Finding and forking

```jennifer
for (def r in forgejo.searchRepositories($c, "jennifer deck")) {
    io.printf("%s %d stars\n", $r.fullName, $r.stars);
}
def mine as forgejo.Repository init forgejo.forkRepository($c, "forgejo/forgejo", "", "");
```

A fork is copied in the background; it may look empty for a moment.

## Settings

```jennifer
forgejo.editRepository($c, "me/app", "An app for X", "https://app.example.com");
forgejo.setDefaultBranch($c, "me/app", "trunk");
forgejo.setArchived($c, "me/old", true);
```

`""` keeps a text as it is. Anything else `editRepository` does not cover
is a `call` with `PATCH /repos/{owner}/{repo}`.

## Who may push

```jennifer
forgejo.addCollaborator($c, "me/app", "ada", "write");
for (def u in forgejo.collaborators($c, "me/app")) {
    io.printf("%s\n", $u.login);
}
forgejo.removeCollaborator($c, "me/app", "ada");
```

A permission is `read`, `write` or `admin`; adding an existing collaborator
changes it.

## Webhooks

```jennifer
def h as forgejo.Hook init forgejo.createHook($c, "me/app", "https://ci.example.com/hook", $secret, ["push", "pull_request"]);
forgejo.deleteHook($c, "me/app", $h.id);
```

The hook posts JSON and signs it with the secret (`X-Forgejo-Signature`,
HMAC-SHA256). Other hook types (Slack, Matrix, ...) go through `call`.
