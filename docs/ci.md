<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Commits and CI

## Reporting a check

A CI system outside Forgejo reports on a commit with a status per check:

```jennifer
forgejo.setCommitStatus($c, "me/app", $sha, "pending", "ci/build", "building", $logUrl);
# ... build ...
forgejo.setCommitStatus($c, "me/app", $sha, "success", "ci/build", "built in 42 s", $logUrl);

def s as forgejo.CombinedStatus init forgejo.combinedStatus($c, "me/app", "main");
io.printf("main is %s over %d checks\n", $s.state, len($s.statuses));
```

A state is `pending`, `success`, `error`, `failure` or `warning`. A new
status for the same context replaces the old one in `combinedStatus`;
`commitStatuses` keeps the history. The token needs `write:repository`.

## Commits

```jennifer
for (def k in forgejo.commits($c, "me/app", "main", "src")) {
    io.printf("%s %s\n", $k.sha, $k.message);
}
```

`commits` follows every page and leaves out file lists and signature
checks, which make a long history slow. `commit` fetches one by SHA, branch
or tag.

## Forgejo Actions

```jennifer
forgejo.setSecret($c, "me/app", "DEPLOY_KEY", fs.readString("deploy.key"));
forgejo.setVariable($c, "me/app", "REGION", "eu-west");
def run as int init forgejo.dispatchWorkflow($c, "me/app", "release.yml", "main", {"level": "minor"});
```

`dispatchWorkflow` needs a `workflow_dispatch` trigger in the workflow.
A secret cannot be read back; `variables` reads the variables. Names are
letters, digits and `_`, and do not start with `FORGEJO_`, `GITEA_` or
`GITHUB_`.
