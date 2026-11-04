<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Connecting

## The address

`client` takes a host name or a URL. A bare host gets `https://`; an
instance below a path keeps it:

```jennifer
def c as forgejo.Client init forgejo.client("codeberg.org");
$c = forgejo.client("https://example.com/git");     # Forgejo at /git
$c = forgejo.client("http://localhost:3000");       # a local test instance
```

A self-hosted instance with its own CA is trusted with `withCaCert`;
`withInsecure` turns certificate checking off.

## Tokens

Create a token under Settings > Applications and give it only the scopes the
program needs: `read:repository` to read, `write:issue` to open and close
issues, `write:repository` for releases and files.

```jennifer
$c = forgejo.withToken($c, fs.readString("/run/secrets/forgejo"));
io.printf("%s\n", forgejo.currentUser($c).login);
```

Without a token the client reads what is public. The token is only sent to
the instance: `downloadAsset` refuses an asset whose URL points elsewhere.

## Any endpoint

`call` takes the path under `/api/v1` with its query string, and the body as
JSON text:

```jennifer
def labels as json.Value init forgejo.call($c, "GET", "/repos/me/app/labels", "");
forgejo.call($c, "POST", "/repos/me/app/labels", '{"name":"bug","color":"#ee0701"}');
```

`getAll` reads every page of a list. Forgejo caps a page at 50 entries by
default and reports the total in `X-Total-Count`; `getAll` follows it, so a
server with a smaller page size is read completely too. It refuses to go
past `MAX_PAGES` pages.

```jennifer
for (def hook in forgejo.getAll($c, "/repos/me/app/hooks")) {
    io.printf("%s\n", json.asString($hook, "/config/url"));
}
```

## Timeouts and retries

`withTimeout` sets each request's idle timeout, 30 s by default. `withRetries`
retries GETs answered 429 or 5xx; writes are never retried.
