<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Releases and files

## Releases

```jennifer
def rel as forgejo.Release init forgejo.createRelease(
    $c, "me/app", "1.2.0", "main", "", $notes, false);
forgejo.uploadAsset($c, "me/app", $rel.id, "app-1.2.0.tar.gz", fs.readBytes("dist/app.tar.gz"));
```

`latestRelease` is the newest release that is neither a draft nor a
pre-release. `editRelease` changes the title or notes, `deleteAsset` an
attached file.

`createRelease` creates the tag at `target` when it does not exist yet; ""
tags the default branch. `release` finds a release by its tag (a tag such as
`release/1.0` included), `releases`
lists them, `deleteRelease` removes one and keeps the tag. A repository with
its Releases unit turned off answers these calls with HTTP 404, as a missing
repository does.

```jennifer
def latest as forgejo.Release init forgejo.release($c, "me/app", "1.2.0");
for (def a in $latest.assets) {
    fs.writeBytes($a.name, forgejo.downloadAsset($c, $a, 268435456));
}
```

`downloadAsset` holds the file in memory and refuses one over its limit,
64 MiB with 0. It only sends the token to the instance itself, and follows no
redirect: an instance that serves assets straight from object storage
answers with one, and `downloadAsset` reports it as a failure.

## Branches and tags

```jennifer
forgejo.createBranch($c, "me/app", "release-1.2", "main");
forgejo.createTag($c, "me/app", "1.2.0", "release-1.2", "Release 1.2.0");
forgejo.deleteBranch($c, "me/app", "release-1.2");
```

A tag with a message is annotated; `""` makes a lightweight one. Protected
branches and tags refuse to be deleted.

```jennifer
for (def b in forgejo.branches($c, "me/app")) {
    io.printf("%s %s\n", $b.name, $b.sha);
}
def newest as forgejo.Tag init forgejo.tags($c, "me/app")[0];
```

## Files

`readFile` reads a file at a branch, tag or commit, a file in Git LFS as its
content; `writeFile` commits a new version, or the first one:

```jennifer
def v as string init convert.stringFromBytes(forgejo.readFile($c, "me/app", "VERSION", "main"), "utf-8");
forgejo.writeFile($c, "me/app", "VERSION", convert.bytesFromString("1.2.1", "utf-8"), "bump to 1.2.1", "main");
```

Each `writeFile` is a commit of its own, and returns its SHA. It reads the
file first to find out whether to create or replace it. `deleteFile` is a
commit too; `listDirectory` lists a directory, `""` the root:

```jennifer
for (def e in forgejo.listDirectory($c, "me/app", "docs", "main")) {
    io.printf("%s %s\n", $e.type, $e.path);
}
forgejo.deleteFile($c, "me/app", "docs/old.md", "drop the old page", "main");
```
