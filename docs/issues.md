<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Issues and pull requests

## Issues

```jennifer
for (def i in forgejo.issues($c, "me/app", "open")) {
    io.printf("#%d %s %v\n", $i.number, $i.title, $i.labels);
}
def made as forgejo.Issue init forgejo.createIssue($c, "me/app", "Nightly build failed", $log);
forgejo.comment($c, "me/app", $made.number, "Fixed in 1.2.1.");
forgejo.closeIssue($c, "me/app", $made.number);
```

`issues` leaves pull requests out; the state is `open`, `closed` or `all`.
`closeIssue`, `reopenIssue`, `comment` and `comments` work on pull requests
too, which share the issue numbers. So do `editIssue`, `setAssignees`,
`setMilestone` and the label verbs.

## Labels and milestones

```jennifer
forgejo.createLabel($c, "me/app", "bug", "#ee0701", "Something is broken");
forgejo.addIssueLabels($c, "me/app", 12, ["bug"]);
def m as forgejo.Milestone init forgejo.createMilestone($c, "me/app", "1.0", "", "2026-12-31T00:00:00Z");
forgejo.setMilestone($c, "me/app", 12, $m.id);
forgejo.editIssue($c, "me/app", 12, "Crash on start with an empty config", "");
```

Label verbs take names. `setIssueLabels` replaces them all, `[]` clears
them. A `scope/name` label is scoped; an exclusive scope allows one label of
it per issue. `""` in `editIssue` keeps the title or text.

## Pull requests

```jennifer
def pr as forgejo.PullRequest init forgejo.createPullRequest(
    $c, "me/app", "update-deps", "main", "Update dependencies", "");
if (forgejo.pullRequest($c, "me/app", $pr.number).mergeable) {
    forgejo.mergePullRequest($c, "me/app", $pr.number, "squash", true);
}
```

The head of a pull request from a fork is `user:branch`. `MERGE_STYLES`
lists the styles: `merge`, `rebase`, `rebase-merge`, `squash` and
`fast-forward-only`; the repository's settings decide which are allowed.
Merging fails with HTTP 405 when the pull request cannot be merged, and 409
when its head moved meanwhile.

## Reviews

```jennifer
forgejo.requestReviewers($c, "me/app", $pr.number, ["ada"]);
for (def f in forgejo.pullRequestFiles($c, "me/app", $pr.number)) {
    io.printf("%s +%d -%d
", $f.filename, $f.additions, $f.deletions);
}
forgejo.reviewPullRequest($c, "me/app", $pr.number, "APPROVED", "");
```

A review is `APPROVED`, `REQUEST_CHANGES` or `COMMENT`; the last two need a
text. A token cannot approve its own pull request.
