<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# forgejo cheatsheet

Every export of `@deckyard/forgejo`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/forgejo/" as forgejo;
```

Every function that sends a request throws `Error{kind: "forgejo"}` when it
fails. A `repo` is `owner/name`; a `number` is an issue or pull request
number.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"forgejo"` | the `kind` of every error the deck throws |
| `PAGE_SIZE` | `50` | entries asked for per page |
| `MAX_PAGES` | `1000` | pages a list follows before it refuses |
| `MERGE_STYLES` | `["merge", "rebase", "rebase-merge", "squash", "fast-forward-only"]` | the ways to merge a pull request |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `url as string` | `https://host`, without `/api/v1` |
| `token as string` | the access token; `""` for anonymous reads |
| `tls as http.TlsOptions` | certificate checking |
| `timeoutMs as int` | idle timeout per request; 0 for 30 s |
| `retries as int` | retries of a GET answered 429 or 5xx |

### `User`

| Field | Meaning |
|---|---|
| `id as int` | the account id |
| `login as string` | the user name |
| `fullName as string` | the display name |
| `email as string` | the e-mail address, as far as the token may see it |
| `isAdmin as bool` | whether it administers the instance |

### `Repository`

| Field | Meaning |
|---|---|
| `id as int` | the repository id |
| `owner as string` | the owning user or organization |
| `name as string` | the name |
| `fullName as string` | `owner/name` |
| `description as string` | the description |
| `isPrivate as bool` | whether it is private |
| `isFork as bool` | whether it is a fork |
| `isArchived as bool` | whether it is archived |
| `defaultBranch as string` | e.g. `main` |
| `htmlUrl as string` | its page |
| `cloneUrl as string` | the HTTPS clone URL |
| `sshUrl as string` | the SSH clone URL |
| `stars as int` | the star count |
| `openIssues as int` | open issues |
| `updated as string` | last update, RFC 3339 |

### `Issue`

| Field | Meaning |
|---|---|
| `number as int` | the number within the repository |
| `title as string` | the title |
| `body as string` | the text, Markdown |
| `state as string` | `open` or `closed` |
| `author as string` | who opened it |
| `labels as list of string` | label names |
| `assignees as list of string` | assigned user names |
| `comments as int` | the comment count |
| `isPull as bool` | whether it is a pull request |
| `created as string` | RFC 3339 |
| `updated as string` | RFC 3339 |
| `closed as string` | RFC 3339; `""` while open |
| `htmlUrl as string` | its page |

### `Comment`

| Field | Meaning |
|---|---|
| `id as int` | the comment id |
| `author as string` | who wrote it |
| `body as string` | the text, Markdown |
| `created as string` | RFC 3339 |
| `htmlUrl as string` | its place on the page |

### `PullRequest`

| Field | Meaning |
|---|---|
| `number as int` | the number within the repository |
| `title as string` | the title |
| `body as string` | the text, Markdown |
| `state as string` | `open` or `closed` |
| `author as string` | who opened it |
| `head as string` | the branch with the changes |
| `base as string` | the branch it merges into |
| `headSha as string` | the commit at the head |
| `isDraft as bool` | whether it is a draft |
| `mergeable as bool` | whether Forgejo can merge it |
| `merged as bool` | whether it is merged |
| `mergeSha as string` | the merge commit; `""` until merged |
| `htmlUrl as string` | its page |

### `Asset`

| Field | Meaning |
|---|---|
| `id as int` | the asset id |
| `name as string` | the file name |
| `size as int` | bytes |
| `downloads as int` | the download count |
| `downloadUrl as string` | where it downloads from |

### `Release`

| Field | Meaning |
|---|---|
| `id as int` | the release id |
| `tag as string` | the tag it is for |
| `name as string` | the title |
| `body as string` | the notes, Markdown |
| `isDraft as bool` | whether it is a draft |
| `isPrerelease as bool` | whether it is a pre-release |
| `created as string` | RFC 3339 |
| `published as string` | RFC 3339 |
| `htmlUrl as string` | its page |
| `assets as list of Asset` | the attached files |

### `Branch`

| Field | Meaning |
|---|---|
| `name as string` | the name |
| `sha as string` | the commit it points at |
| `isProtected as bool` | whether a protection rule covers it |

### `Tag`

| Field | Meaning |
|---|---|
| `name as string` | the name |
| `sha as string` | the commit it points at |
| `message as string` | the annotation; `""` for a lightweight tag |

### `CommitStatus`

| Field | Meaning |
|---|---|
| `context as string` | which check, e.g. `ci/build` |
| `state as string` | `pending`, `success`, `error`, `failure` or `warning` |
| `description as string` | a short text |
| `targetUrl as string` | where the details are |
| `creator as string` | who set it |
| `created as string` | RFC 3339 |

### `CombinedStatus`

| Field | Meaning |
|---|---|
| `state as string` | the worst latest state; `""` without statuses |
| `statuses as list of CommitStatus` | the latest status per context |

### `Commit`

| Field | Meaning |
|---|---|
| `sha as string` | the commit SHA |
| `message as string` | the commit message |
| `author as string` | the author's name |
| `authorEmail as string` | the author's e-mail address |
| `date as string` | the author date, RFC 3339 |
| `htmlUrl as string` | its page |

### `Label`

| Field | Meaning |
|---|---|
| `id as int` | the label id |
| `name as string` | e.g. `bug`, `scope/ui` |
| `color as string` | e.g. `#ee0701` |
| `description as string` | the description |
| `exclusive as bool` | whether it excludes the rest of its scope |

### `Milestone`

| Field | Meaning |
|---|---|
| `id as int` | the milestone id |
| `title as string` | the title |
| `description as string` | the description |
| `state as string` | `open` or `closed` |
| `dueOn as string` | RFC 3339; `""` without a due date |
| `openIssues as int` | open issues in it |
| `closedIssues as int` | closed issues in it |

### `Review`

| Field | Meaning |
|---|---|
| `id as int` | the review id |
| `author as string` | who reviewed |
| `state as string` | `APPROVED`, `REQUEST_CHANGES`, `COMMENT`, `PENDING` or `REQUEST_REVIEW` |
| `body as string` | the text, Markdown |
| `commitId as string` | the commit it reviewed |
| `submitted as string` | RFC 3339 |

### `ChangedFile`

| Field | Meaning |
|---|---|
| `filename as string` | the path |
| `status as string` | e.g. `added`, `changed`, `deleted`, `renamed` |
| `additions as int` | lines added |
| `deletions as int` | lines deleted |
| `previousFilename as string` | the old path of a renamed file |

### `Hook`

| Field | Meaning |
|---|---|
| `id as int` | the hook id |
| `type as string` | e.g. `forgejo`, `slack` |
| `url as string` | where it posts to |
| `events as list of string` | e.g. `push` |
| `active as bool` | whether it fires |

### `Entry`

| Field | Meaning |
|---|---|
| `name as string` | the name |
| `path as string` | the path from the root |
| `type as string` | `file`, `dir`, `symlink` or `submodule` |
| `size as int` | bytes; 0 for a directory |
| `sha as string` | the blob or tree SHA |

## Connecting

| Function | Returns | Does |
|---|---|---|
| `forgejo.client(address)` | `Client` | a client for an instance, without a token |
| `forgejo.withToken(c, token)` | `Client` | authenticate with an access token |
| `forgejo.withCaCert(c, pem)` | `Client` | trust a certificate |
| `forgejo.withInsecure(c)` | `Client` | accept any certificate |
| `forgejo.withTimeout(c, ms)` | `Client` | set the idle timeout |
| `forgejo.withRetries(c, n)` | `Client` | retry GETs answered 429 or 5xx |
| `forgejo.call(c, method, path, body)` | `json.Value` | any endpoint; `body` is JSON text |
| `forgejo.getAll(c, path)` | `list of json.Value` | every page of a list endpoint |
| `forgejo.version(c)` | `string` | the instance's version |
| `forgejo.currentUser(c)` | `User` | the token's account |

## Repositories

| Function | Returns | Does |
|---|---|---|
| `forgejo.repository(c, repo)` | `Repository` | one repository |
| `forgejo.repositories(c, owner)` | `list of Repository` | a user's or organization's repositories |
| `forgejo.myRepositories(c)` | `list of Repository` | the token's own and shared repositories |
| `forgejo.createRepository(c, owner, name, description, isPrivate)` | `Repository` | an empty repository; owner `""` for the token's account |
| `forgejo.deleteRepository(c, repo)` | | delete it, with no undo |
| `forgejo.editRepository(c, repo, description, website)` | `Repository` | change them; `""` keeps |
| `forgejo.setArchived(c, repo, archived)` | `Repository` | archive it or bring it back |
| `forgejo.setDefaultBranch(c, repo, branch)` | `Repository` | change the default branch |
| `forgejo.forkRepository(c, repo, organization, name)` | `Repository` | fork it; `""` for your account, the same name |
| `forgejo.searchRepositories(c, query)` | `list of Repository` | search names and descriptions |
| `forgejo.collaborators(c, repo)` | `list of User` | the collaborators |
| `forgejo.addCollaborator(c, repo, name, permission)` | | `read`, `write` or `admin` |
| `forgejo.removeCollaborator(c, repo, name)` | | remove one |
| `forgejo.hooks(c, repo)` | `list of Hook` | the webhooks |
| `forgejo.createHook(c, repo, url, secret, events)` | `Hook` | a Forgejo webhook posting JSON |
| `forgejo.deleteHook(c, repo, id)` | | delete one |
| `forgejo.branches(c, repo)` | `list of Branch` | the branches |
| `forgejo.tags(c, repo)` | `list of Tag` | the tags, newest first |
| `forgejo.createBranch(c, repo, name, from)` | `Branch` | branch off a ref; `""` for the default branch |
| `forgejo.deleteBranch(c, repo, name)` | | delete a branch |
| `forgejo.createTag(c, repo, name, target, message)` | `Tag` | tag a ref; `""` message for a lightweight tag |
| `forgejo.deleteTag(c, repo, name)` | | delete a tag |
| `forgejo.readFile(c, repo, path, ref)` | `bytes` | a file at a ref, LFS content included; `""` for the default branch |
| `forgejo.writeFile(c, repo, path, data, message, branch)` | `string` | commit a file; the commit SHA |
| `forgejo.deleteFile(c, repo, path, message, branch)` | `string` | delete a file; the commit SHA |
| `forgejo.listDirectory(c, repo, path, ref)` | `list of Entry` | a directory's entries; `""` for the root |

## Issues and pull requests

| Function | Returns | Does |
|---|---|---|
| `forgejo.issues(c, repo, state)` | `list of Issue` | issues, without pull requests |
| `forgejo.issue(c, repo, number)` | `Issue` | one issue |
| `forgejo.createIssue(c, repo, title, body)` | `Issue` | open an issue |
| `forgejo.closeIssue(c, repo, number)` | `Issue` | close an issue or pull request |
| `forgejo.reopenIssue(c, repo, number)` | `Issue` | reopen one |
| `forgejo.comments(c, repo, number)` | `list of Comment` | its comments, oldest first |
| `forgejo.comment(c, repo, number, body)` | `Comment` | add a comment |
| `forgejo.editComment(c, repo, id, body)` | `Comment` | change a comment |
| `forgejo.deleteComment(c, repo, id)` | | delete a comment |
| `forgejo.editIssue(c, repo, number, title, body)` | `Issue` | change title or text; `""` keeps |
| `forgejo.setAssignees(c, repo, number, names)` | `Issue` | set who is assigned |
| `forgejo.setMilestone(c, repo, number, milestoneId)` | `Issue` | put it in a milestone; 0 for none |
| `forgejo.labels(c, repo)` | `list of Label` | the repository's labels |
| `forgejo.createLabel(c, repo, name, color, description)` | `Label` | create a label |
| `forgejo.deleteLabel(c, repo, id)` | | delete a label |
| `forgejo.setIssueLabels(c, repo, number, names)` | `list of Label` | replace its labels |
| `forgejo.addIssueLabels(c, repo, number, names)` | `list of Label` | add labels |
| `forgejo.removeIssueLabel(c, repo, number, name)` | | take a label off |
| `forgejo.milestones(c, repo, state)` | `list of Milestone` | the milestones |
| `forgejo.createMilestone(c, repo, title, description, dueOn)` | `Milestone` | create one |
| `forgejo.setMilestoneClosed(c, repo, id, closed)` | `Milestone` | close or reopen one |
| `forgejo.deleteMilestone(c, repo, id)` | | delete one |
| `forgejo.pullRequests(c, repo, state)` | `list of PullRequest` | pull requests |
| `forgejo.pullRequest(c, repo, number)` | `PullRequest` | one pull request |
| `forgejo.createPullRequest(c, repo, head, base, title, body)` | `PullRequest` | open a pull request |
| `forgejo.mergePullRequest(c, repo, number, style, deleteBranch)` | | merge it |
| `forgejo.editPullRequest(c, repo, number, title, body)` | `PullRequest` | change title or text; `""` keeps |
| `forgejo.reviewPullRequest(c, repo, number, event, body)` | `Review` | `APPROVED`, `REQUEST_CHANGES` or `COMMENT` |
| `forgejo.reviews(c, repo, number)` | `list of Review` | its reviews |
| `forgejo.requestReviewers(c, repo, number, names)` | | ask users to review |
| `forgejo.pullRequestFiles(c, repo, number)` | `list of ChangedFile` | the files it changes |

## Releases

| Function | Returns | Does |
|---|---|---|
| `forgejo.releases(c, repo)` | `list of Release` | the releases, newest first |
| `forgejo.release(c, repo, tag)` | `Release` | the release of a tag |
| `forgejo.latestRelease(c, repo)` | `Release` | the newest that is no draft or pre-release |
| `forgejo.editRelease(c, repo, id, name, body)` | `Release` | change title or notes; `""` keeps |
| `forgejo.createRelease(c, repo, tag, target, name, body, isPrerelease)` | `Release` | publish a release |
| `forgejo.deleteRelease(c, repo, id)` | | delete it; the tag stays |
| `forgejo.uploadAsset(c, repo, releaseId, name, data)` | `Asset` | attach a file |
| `forgejo.downloadAsset(c, asset, maxBytes)` | `bytes` | download a file from the instance |
| `forgejo.deleteAsset(c, repo, releaseId, assetId)` | | delete an attached file |

## Commits and CI

| Function | Returns | Does |
|---|---|---|
| `forgejo.commits(c, repo, ref, path)` | `list of Commit` | commits from a ref; `path` narrows them |
| `forgejo.commit(c, repo, sha)` | `Commit` | one commit |
| `forgejo.setCommitStatus(c, repo, sha, state, context, description, targetUrl)` | `CommitStatus` | report a check on a commit |
| `forgejo.commitStatuses(c, repo, ref)` | `list of CommitStatus` | every status set on it |
| `forgejo.combinedStatus(c, repo, ref)` | `CombinedStatus` | the latest per check, and the worst |
| `forgejo.dispatchWorkflow(c, repo, workflow, ref, inputs)` | `int` | run a workflow; the run id |
| `forgejo.setSecret(c, repo, name, value)` | | create or replace an Actions secret |
| `forgejo.deleteSecret(c, repo, name)` | | delete one |
| `forgejo.variables(c, repo)` | `map of string to string` | the Actions variables |
| `forgejo.setVariable(c, repo, name, value)` | | create or replace one |
| `forgejo.deleteVariable(c, repo, name)` | | delete one |
