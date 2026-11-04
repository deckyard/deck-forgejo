# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * Summarize a repository: its latest release and the open issues without
 * a label.
 *
 *   jennifer run examples/triage.j forgejo/forgejo
 *
 * Reads public data anonymously from Codeberg; set FORGEJO_URL and
 * FORGEJO_TOKEN for another instance or a private repository.
 */
use io;
use os;

import "../src/forgejo.j" as forgejo;

if (len(os.ARGS) != 2) {
    throw Error{kind: "usage", message: "usage: triage.j <owner/name>"};
}
def repo as string init os.ARGS[1];

def url as string init "codeberg.org";
if (os.hasEnv("FORGEJO_URL")) {
    $url = os.getEnv("FORGEJO_URL");
}
def c as forgejo.Client init forgejo.withRetries(forgejo.client($url), 2);
if (os.hasEnv("FORGEJO_TOKEN")) {
    $c = forgejo.withToken($c, os.getEnv("FORGEJO_TOKEN"));
}

def r as forgejo.Repository init forgejo.repository($c, $repo);
io.printf("%s: %d open issues, default branch %s\n", $r.fullName, $r.openIssues, $r.defaultBranch);

# A repository with releases turned off answers 404 here.
try {
    def rel as list of forgejo.Release init forgejo.releases($c, $repo);
    if (len($rel) > 0) {
        io.printf("latest release %s, %d assets\n", $rel[0].tag, len($rel[0].assets));
    }
} catch (e) {
    io.printf("no releases: %s\n", $e.message);
}

for (def i in forgejo.issues($c, $repo, "open")) {
    if (len($i.labels) == 0) {
        io.printf("  unlabelled #%d %s\n", $i.number, $i.title);
    }
}
