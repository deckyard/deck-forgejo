<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

A client for the Forgejo™ REST API (`/api/v1`), for Codeberg™ or a self-hosted
Forgejo; Gitea™ speaks mostly the same API. Typed verbs cover repositories and
their settings, issues, labels, milestones, pull requests and reviews,
releases and assets, branches, tags, files, commit statuses and Actions
(workflow dispatch, variables, secrets). `call` and `getAll` reach any other
endpoint.

The deck is also one of the three backends of `@deckyard/codehost`, which
puts one API over GitHub™, GitLab™ and Forgejo; several fields and fixes exist
because codehost needed them.

Out of scope:

- Running git. The deck talks HTTP only (no `exec`); clones and pushes are
  for git itself.
- Typed verbs for every endpoint. The API is large; the rest is reachable
  through `call` and `getAll`.
- `jennifer-tiny`, which lacks `net`.

## Decisions

- **One module, one `Client` value.** `client(address)` normalises the base
  URL (a bare host gets `https://`, a trailing `/` and `/api/v1` are
  dropped, a sub-path is kept). `withToken`, `withCaCert`, `withInsecure`,
  `withTimeout`, `withRetries` and `withPlainHttp` return adjusted copies.
- **Input is validated before it reaches a URL.** Repository paths are
  `owner/name` without `.` or `..`; paths may not contain `//`, `#`, spaces
  or dot segments. Two encoders on purpose: file paths are checked and
  percent-encoded segment by segment, while refs, workflow names and tags
  are validated and encoded as one segment.
- **Tolerant reading, strict writing.** Replies are parsed with accessors
  that read an absent or `null` member as the zero value and accept numbers
  sent as strings, since Forgejo and Gitea versions differ in what they omit.
  Request bodies leave out empty string fields, so the `edit*` verbs take
  `""` as "keep" and cannot clear a field.
- **Only reads are retried.** `withRetries` applies to GETs answered 429 or
  5xx, with a 500 ms backoff. Writes are never retried, as they need not be
  idempotent, and a network failure is never retried by the deck.
- **Paging.** `getAll` pages with `limit` `PAGE_SIZE` (50), stops at
  `X-Total-Count`, else at a short page, and refuses to go past `MAX_PAGES`
  (1000).
- **Byte transfers bypass the JSON path.** `uploadAsset` sends a multipart
  body; `readFile` reads through `/media/`, so LFS files come back as
  content; `downloadAsset` and `readFile` take a size cap (0 for 64 MiB) and
  follow up to five redirects for instances that serve storage directly.
- **Labels by id where the server needs it.** `removeIssueLabel` reads the
  issue's labels and deletes by id: Gitea 1.24 accepts only an id, and
  Forgejo 13 answered 422 for an absent label by name. Removing an absent
  label does nothing. Setting or adding unknown label names is not an error
  on the server; it drops them.
- **Server quirks are absorbed where they mislead.** After a merge deletes
  the head branch, Forgejo reports `refs/pull/<n>/head` as the ref, so the
  branch name is taken from the label. `commitStatuses` sorts by id, newest
  first, because Forgejo orders by time to the second and lists same-second
  statuses oldest first. `PullRequest.headRepo` is `""` once a fork is gone.
- **Variable names Forgejo rejects** (`FORGEJO_`, `GITEA_` and `GITHUB_`
  prefixes, a leading digit) are refused locally.

## Errors

Every error of kind `"forgejo"` (`ERROR_KIND`) is a `ForgejoError{kind,
message, status}`: `status` is the HTTP status, 0 for a local check or a
failure without an answer. The message is `forgejo: <verb> <path>: <cause>`,
where the cause is Forgejo's `message` plus its validation `errors`. Callers
branch on `$e.kind == ERROR_KIND and $e.status == 404`; the deck itself does
so to tell create from update in `writeFile` and `setVariable`.

A request without a usable answer keeps the generic kind of its cause, with
the request in front of the message: `"limit"` (a body cap, a reply nested
past the JSON decoder's caps, more than five redirects, or paging past
`MAX_PAGES`), `"timeout"` and `"closed"`. A network failure (refused, reset,
unreachable, DNS, TLS) passes on unchanged as the `net.NetError` (kind
`"net"`) that `http` threw, with its `op`, `reason`, `sent` and `replied`. A
cancelled task passes on unchanged too. Any other transport failure is a
`ForgejoError` with status 0.

A helper that receives a caught deck error is typed `ForgejoError`, not
`Error`.

## Security and limits

- **The token stays on the instance.** `downloadAsset` refuses a download
  URL not under the client's base URL; redirects carry the token only to the
  instance's own URLs, and an https to http redirect is refused. Messages
  drop a URL's query, which may hold a storage signature.
- **Plain http only to this machine** (`127.0.0.1`, `localhost`, `[::1]`)
  unless `withPlainHttp`. The check runs before every request, so a client
  built for `http://git.lan:3000` fails before sending its token.
- `withInsecure` skips certificate verification; `withCaCert` is the safer
  way to trust a private CA.
- Caller and server strings in messages are cut (60 characters for quoted
  values, 200 for the server's reason) with anything but printable ASCII
  shown as `?`, so a message stays one line and carries no terminal escape.
- Timeouts: 30 s by default; negative timeouts and retry counts are refused.

## Testing and validation

- `src/forgejo_test.j` runs every verb against an `httpd` fake on loopback
  that answers canned replies in order and records each request (method,
  decoded path, query, auth, content type, body). Assertions cover what was
  sent as much as what was parsed.
- Live, 2026-11-14 (through the codehost validation): reads on Codeberg,
  and every write verb against Forgejo 13.0.5 and Gitea 1.24.7 in throwaway
  containers.
- The example reads Codeberg live, so CI only parses it.

## Known limitations and open questions

- `edit*` verbs cannot clear a string field.
- A Forgejo lightweight tag reports its commit's message as the tag message.
- Bodies are read whole; large downloads wait for streaming responses in
  `http` (M30.9).

## Dependencies on the interpreter

Floor `>=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms), capability `net`, for the UTF-8 codecs of
`encoding.encode` / `decode` and `strings.replicate`; the example also uses
`os.hasEnv` (0.26.0). It uses the bundled
`http`, `multipart` and `uri` modules. From `jennifer`'s milestones: M28.57
(the error conventions) and M28.65 (transport failures as `net.NetError`,
kind `"net"`, which the deck passes on).
