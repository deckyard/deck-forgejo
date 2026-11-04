# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the Forgejo REST API (`/api/v1`).
 *
 * A thin client: `call` reaches any endpoint and `getAll` follows the pages
 * of a list. Typed verbs cover the daily work: repositories, issues and
 * comments, pull requests, releases and their assets, branches, tags and
 * files. Gitea speaks the same API, so most of it works there too.
 *
 * A `Client` authenticates with an access token (`withToken`). Every
 * failure is `Error{kind: "forgejo"}`.
 *
 * @module forgejo
 * @see https://forgejo.org/docs/latest/user/api-usage/
 * @example
 *   def c as forgejo.Client init forgejo.withToken(forgejo.client("codeberg.org"), $token);
 *   for (def i in forgejo.issues($c, "forgejo/forgejo", "open")) {
 *       io.printf("#%d %s\n", $i.number, $i.title);
 *   }
 */
use convert;
use encoding;
use json;
use lists;
use maps;
use regex;
use strings;
import "http.j" as http;
import "multipart.j" as multipart;
import "uri.j" as uri;

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "forgejo";

/** The entries `getAll` and the list verbs ask for per page. */
export def const PAGE_SIZE as int init 50;

/** The most pages a list follows before it refuses: 50000 entries. */
export def const MAX_PAGES as int init 1000;

/** The ways `mergePullRequest` can merge. */
export def const MERGE_STYLES as list of string init [
    "merge",
    "rebase",
    "rebase-merge",
    "squash",
    "fast-forward-only"
];

/**
 * A connection to one Forgejo instance.
 *
 * @field url {string} `https://host`, without `/api/v1`
 * @field token {string} the access token; "" for anonymous reads
 * @field tls {http.TlsOptions} certificate checking
 * @field timeoutMs {int} the idle timeout of each request; 0 for 30 s
 * @field retries {int} retries of a GET answered 429 or 5xx
 */
export def struct Client {
    url as string,
    token as string,
    tls as http.TlsOptions,
    timeoutMs as int,
    retries as int
};

/**
 * An account.
 *
 * @field id {int} the account id
 * @field login {string} the user name
 * @field fullName {string} the display name
 * @field email {string} the e-mail address, as far as the token may see it
 * @field isAdmin {bool} whether it administers the instance
 */
export def struct User {
    id as int,
    login as string,
    fullName as string,
    email as string,
    isAdmin as bool
};

/**
 * A repository.
 *
 * @field id {int} the repository id
 * @field owner {string} the owning user or organization
 * @field name {string} the name
 * @field fullName {string} `owner/name`
 * @field description {string} the description
 * @field isPrivate {bool} whether it is private
 * @field isFork {bool} whether it is a fork
 * @field isArchived {bool} whether it is archived
 * @field defaultBranch {string} e.g. `main`
 * @field htmlUrl {string} its page
 * @field cloneUrl {string} the HTTPS clone URL
 * @field sshUrl {string} the SSH clone URL
 * @field stars {int} the star count
 * @field openIssues {int} open issues
 * @field updated {string} last update, RFC 3339
 */
export def struct Repository {
    id as int,
    owner as string,
    name as string,
    fullName as string,
    description as string,
    isPrivate as bool,
    isFork as bool,
    isArchived as bool,
    defaultBranch as string,
    htmlUrl as string,
    cloneUrl as string,
    sshUrl as string,
    stars as int,
    openIssues as int,
    updated as string
};

/**
 * An issue.
 *
 * @field number {int} the number within the repository
 * @field title {string} the title
 * @field body {string} the text, Markdown
 * @field state {string} `open` or `closed`
 * @field author {string} who opened it
 * @field labels {list of string} label names
 * @field assignees {list of string} assigned user names
 * @field comments {int} the comment count
 * @field isPull {bool} whether it is a pull request
 * @field created {string} RFC 3339
 * @field updated {string} RFC 3339
 * @field closed {string} RFC 3339; "" while open
 * @field htmlUrl {string} its page
 */
export def struct Issue {
    number as int,
    title as string,
    body as string,
    state as string,
    author as string,
    labels as list of string,
    assignees as list of string,
    comments as int,
    isPull as bool,
    created as string,
    updated as string,
    closed as string,
    htmlUrl as string
};

/**
 * A comment on an issue or pull request.
 *
 * @field id {int} the comment id
 * @field author {string} who wrote it
 * @field body {string} the text, Markdown
 * @field created {string} RFC 3339
 * @field htmlUrl {string} its place on the page
 */
export def struct Comment {
    id as int,
    author as string,
    body as string,
    created as string,
    htmlUrl as string
};

/**
 * A pull request.
 *
 * @field number {int} the number within the repository
 * @field title {string} the title
 * @field body {string} the text, Markdown
 * @field state {string} `open` or `closed`
 * @field author {string} who opened it
 * @field head {string} the branch with the changes
 * @field base {string} the branch it merges into
 * @field headSha {string} the commit at the head
 * @field isDraft {bool} whether it is a draft
 * @field mergeable {bool} whether Forgejo can merge it
 * @field merged {bool} whether it is merged
 * @field mergeSha {string} the merge commit; "" until merged
 * @field htmlUrl {string} its page
 */
export def struct PullRequest {
    number as int,
    title as string,
    body as string,
    state as string,
    author as string,
    head as string,
    base as string,
    headSha as string,
    isDraft as bool,
    mergeable as bool,
    merged as bool,
    mergeSha as string,
    htmlUrl as string
};

/**
 * A file attached to a release.
 *
 * @field id {int} the asset id
 * @field name {string} the file name
 * @field size {int} bytes
 * @field downloads {int} the download count
 * @field downloadUrl {string} where it downloads from
 */
export def struct Asset {
    id as int,
    name as string,
    size as int,
    downloads as int,
    downloadUrl as string
};

/**
 * A release.
 *
 * @field id {int} the release id
 * @field tag {string} the tag it is for
 * @field name {string} the title
 * @field body {string} the notes, Markdown
 * @field isDraft {bool} whether it is a draft
 * @field isPrerelease {bool} whether it is a pre-release
 * @field created {string} RFC 3339
 * @field published {string} RFC 3339
 * @field htmlUrl {string} its page
 * @field assets {list of Asset} the attached files
 */
export def struct Release {
    id as int,
    tag as string,
    name as string,
    body as string,
    isDraft as bool,
    isPrerelease as bool,
    created as string,
    published as string,
    htmlUrl as string,
    assets as list of Asset
};

/**
 * A branch.
 *
 * @field name {string} the name
 * @field sha {string} the commit it points at
 * @field isProtected {bool} whether a protection rule covers it
 */
export def struct Branch {
    name as string,
    sha as string,
    isProtected as bool
};

/**
 * A tag.
 *
 * @field name {string} the name
 * @field sha {string} the commit it points at
 * @field message {string} the annotation; "" for a lightweight tag
 */
export def struct Tag {
    name as string,
    sha as string,
    message as string
};

/**
 * The status a CI system set on a commit.
 *
 * @field context {string} which check it is, e.g. `ci/build`
 * @field state {string} `pending`, `success`, `error`, `failure` or `warning`
 * @field description {string} a short text
 * @field targetUrl {string} where the details are
 * @field creator {string} who set it
 * @field created {string} RFC 3339
 */
export def struct CommitStatus {
    context as string,
    state as string,
    description as string,
    targetUrl as string,
    creator as string,
    created as string
};

/**
 * The statuses of a commit, combined.
 *
 * @field state {string} the worst state of the latest status per context;
 *   "" when there is none
 * @field statuses {list of CommitStatus} the latest status per context
 */
export def struct CombinedStatus {
    state as string,
    statuses as list of CommitStatus
};

/**
 * A commit.
 *
 * @field sha {string} the commit SHA
 * @field message {string} the commit message
 * @field author {string} the author's name, as Git records it
 * @field authorEmail {string} the author's e-mail address
 * @field date {string} the author date, RFC 3339
 * @field htmlUrl {string} its page
 */
export def struct Commit {
    sha as string,
    message as string,
    author as string,
    authorEmail as string,
    date as string,
    htmlUrl as string
};

/**
 * A label of a repository.
 *
 * @field id {int} the label id
 * @field name {string} the name, e.g. `bug` or `scope/ui`
 * @field color {string} the colour, e.g. `#ee0701`
 * @field description {string} the description
 * @field exclusive {bool} whether it excludes the other labels of its scope
 */
export def struct Label {
    id as int,
    name as string,
    color as string,
    description as string,
    exclusive as bool
};

/**
 * A milestone of a repository.
 *
 * @field id {int} the milestone id
 * @field title {string} the title
 * @field description {string} the description
 * @field state {string} `open` or `closed`
 * @field dueOn {string} RFC 3339; "" without a due date
 * @field openIssues {int} open issues in it
 * @field closedIssues {int} closed issues in it
 */
export def struct Milestone {
    id as int,
    title as string,
    description as string,
    state as string,
    dueOn as string,
    openIssues as int,
    closedIssues as int
};

/**
 * A review of a pull request.
 *
 * @field id {int} the review id
 * @field author {string} who reviewed
 * @field state {string} `APPROVED`, `REQUEST_CHANGES`, `COMMENT`, `PENDING`
 *   or `REQUEST_REVIEW`
 * @field body {string} the text, Markdown
 * @field commitId {string} the commit it reviewed
 * @field submitted {string} RFC 3339
 */
export def struct Review {
    id as int,
    author as string,
    state as string,
    body as string,
    commitId as string,
    submitted as string
};

/**
 * A file a pull request changes.
 *
 * @field filename {string} the path
 * @field status {string} e.g. `added`, `changed`, `deleted`, `renamed`
 * @field additions {int} lines added
 * @field deletions {int} lines deleted
 * @field previousFilename {string} the old path of a renamed file; ""
 *   otherwise
 */
export def struct ChangedFile {
    filename as string,
    status as string,
    additions as int,
    deletions as int,
    previousFilename as string
};

/**
 * A webhook of a repository.
 *
 * @field id {int} the hook id
 * @field type {string} e.g. `forgejo`, `slack`, `matrix`
 * @field url {string} where it posts to
 * @field events {list of string} the events it fires on, e.g. `push`
 * @field active {bool} whether it fires
 */
export def struct Hook {
    id as int,
    type as string,
    url as string,
    events as list of string,
    active as bool
};

/**
 * An entry of a directory in a repository.
 *
 * @field name {string} the name
 * @field path {string} the path from the repository root
 * @field type {string} `file`, `dir`, `symlink` or `submodule`
 * @field size {int} bytes; 0 for a directory
 * @field sha {string} the blob or tree SHA
 */
export def struct Entry {
    name as string,
    path as string,
    type as string,
    size as int,
    sha as string
};

# An owner or repository name as Forgejo allows it.
def const NAME_PATTERN as string init "^[A-Za-z0-9_.-]+$";

# How much of a string an error message repeats.
def const SHOWN as int init 60;

# How much of the server's reason for a refusal an error message repeats.
def const REASON as int init 200;

# The idle timeout a `timeoutMs` of 0 stands for, as `http.send` has it.
def const DEFAULT_TIMEOUT_MS as int init 30000;

func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: "forgejo: " + $message};
}

/**
 * A string fit for an error message: cut to `most` characters, with
 * anything but printable ASCII as `?`, so a message stays one line and
 * carries no terminal escape into a log.
 *
 * @param text {string} a caller's or the server's string
 * @param most {int} the characters kept
 * @return {string} the text
 */
func plain(text as string, most as int) {
    def cut as string init $text;
    def more as string init "";
    if (len($text) > $most) {
        $cut = strings.substring($text, 0, $most);
        $more = "...";
    }
    return regex.replace("[^ -~]", $cut, "?") + $more;
}

/**
 * A string as an error message quotes it: `plain`, cut to `SHOWN`.
 *
 * @param text {string} a caller's or the server's string
 * @return {string} the text in double quotes
 */
func shown(text as string) {
    return "\"" + plain($text, SHOWN) + "\"";
}

/**
 * The base URL for a host name or URL. A bare host gets `https://`; a
 * trailing slash and a trailing `/api/v1` are dropped.
 *
 * @param address {string} `codeberg.org`, `git.example.com:3000` or a full URL
 * @return {string} `https://host[:port]`
 */
func baseUrl(address as string) {
    def url as string init strings.trim($address);
    if ($url == "") {
        fail("the host is empty");
    }
    while (strings.endsWith($url, "/")) {
        $url = strings.substring($url, 0, len($url) - 1);
    }
    if (strings.endsWith($url, "/api/v1")) {
        $url = strings.substring($url, 0, len($url) - len("/api/v1"));
    }
    if (strings.contains($url, "://")) {
        return $url;
    }
    return "https://" + $url;
}

/**
 * A client for an instance, without a token.
 *
 * @param address {string} host name, `host:port` or a full URL; a Forgejo
 *   below a path, such as `https://example.com/git`, keeps the path
 * @return {Client} the client; full certificate checking
 * @throws {Error} kind `"forgejo"` when the address is empty
 * @example
 *   def c as forgejo.Client init forgejo.client("codeberg.org");
 */
export func client(address as string) {
    def c as Client;
    $c.url = baseUrl($address);
    return $c;
}

/**
 * Authenticate with an access token, made under Settings > Applications.
 * Give it only the scopes the program needs.
 *
 * @param c {Client} the client
 * @param token {string} the token
 * @return {Client} the changed copy
 * @throws {Error} kind `"forgejo"` when the token holds spaces or control
 *   characters
 */
export func withToken(c as Client, token as string) {
    if (regex.matches("[\\s\\x00-\\x1f\\x7f]", $token)) {
        fail("a token holds no spaces or control characters");
    }
    $c.token = $token;
    return $c;
}

/**
 * Trust a certificate (PEM) in addition to the system's, for an instance
 * with a private CA or a self-signed certificate.
 *
 * @param c {Client} the client
 * @param pem {bytes} the certificate
 * @return {Client} the changed copy
 */
export func withCaCert(c as Client, pem as bytes) {
    $c.tls.caCert = $pem;
    $c.tls.skipVerify = false;
    return $c;
}

/**
 * Accept any certificate. The connection is still encrypted but no longer
 * authenticated; prefer `withCaCert`.
 *
 * @param c {Client} the client
 * @return {Client} the changed copy
 */
export func withInsecure(c as Client) {
    $c.tls.skipVerify = true;
    return $c;
}

/**
 * Set the idle timeout of each request.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds; 0 for the default, 30 s
 * @return {Client} the changed copy
 */
export func withTimeout(c as Client, ms as int) {
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * Retry a GET answered 429 or 5xx. Writes are never retried: they need not
 * be idempotent.
 *
 * @param c {Client} the client
 * @param n {int} retries, 0 for none
 * @return {Client} the changed copy
 */
export func withRetries(c as Client, n as int) {
    $c.retries = $n;
    return $c;
}

/**
 * Refuse an API path that would not address what it says.
 *
 * @param path {string} the path under `/api/v1`, query string allowed
 */
func ensurePath(path as string) {
    if (not strings.startsWith($path, "/")) {
        fail("an API path starts with /, got " + shown($path));
    }
    def route as string init $path;
    if (strings.contains($route, "?")) {
        $route = strings.substring($route, 0, strings.indexOf($route, "?"));
    }
    if (strings.contains($route, "//") or strings.contains($route, "#") or
        regex.matches("[\\x00-\\x20\\x7f]", $path)) {
        fail("an API path holds no //, # or spaces: " + shown($path));
    }
    for (def segment in strings.split($route, "/")) {
        if ($segment == "." or $segment == "..") {
            fail("an API path has no . or .. segments: " + shown($path));
        }
    }
}

/**
 * The `owner/name` of a repository, checked.
 *
 * @param repo {string} `owner/name`
 * @return {string} `/repos/owner/name`
 */
func repoPath(repo as string) {
    def parts as list of string init strings.split($repo, "/");
    if (len($parts) != 2) {
        fail("a repository is owner/name, got " + shown($repo));
    }
    for (def part in $parts) {
        if (not regex.matches(NAME_PATTERN, $part) or $part == "." or $part == "..") {
            fail("a repository is owner/name, got " + shown($repo));
        }
    }
    return "/repos/" + $repo;
}

/**
 * An owner name, checked.
 *
 * @param owner {string} a user or organization
 * @return {string} the name
 */
func checkOwner(owner as string) {
    if (not regex.matches(NAME_PATTERN, $owner) or $owner == "." or $owner == "..") {
        fail("an owner is a user or organization name, got " + shown($owner));
    }
    return $owner;
}

/**
 * A ref, tag or file path for a URL: each segment percent-encoded.
 *
 * @param text {string} e.g. `docs/a b.md` or `release/1.0`
 * @param what {string} what it is, for the error message
 * @return {string} the encoded path
 */
func segments(text as string, what as string) {
    if ($text == "" or regex.matches("[\\x00-\\x1f\\x7f]", $text)) {
        fail("a " + $what + " is not empty and holds no control characters, got " + shown($text));
    }
    def out as list of string init [];
    for (def part in strings.split($text, "/")) {
        if ($part == "" or $part == "." or $part == "..") {
            fail("a " + $what + " has no empty, . or .. segments, got " + shown($text));
        }
        $out[] = uri.encode($part);
    }
    return strings.join($out, "/");
}

/**
 * A ref or name that goes into a URL as one segment, checked as `segments`
 * checks it but not encoded: the caller encodes it whole.
 *
 * @param text {string} the ref or name
 * @param what {string} what it is, for the error message
 * @return {string} the text as given
 */
func checked(text as string, what as string) {
    segments($text, $what);
    return $text;
}

/**
 * The headers that carry the credential.
 *
 * @param c {Client} the client
 * @return {map of string to string} the headers
 */
func authHeaders(c as Client) {
    def headers as map of string to string init {"Accept": "application/json"};
    if ($c.token != "") {
        $headers["Authorization"] = "token " + $c.token;
    }
    return $headers;
}

/**
 * The idle timeout for the `http` calls that take it directly, where 0
 * would mean no timeout at all.
 *
 * @param c {Client} the client
 * @return {int} milliseconds
 */
func idleMs(c as Client) {
    if ($c.timeoutMs == 0) {
        return DEFAULT_TIMEOUT_MS;
    }
    return $c.timeoutMs;
}

/**
 * Send a request and return the response, a non-2xx refused.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param path {string} the path under `/api/v1`
 * @param body {string} JSON, or "" for none
 * @return {http.Response} the response
 */
func exchange(c as Client, method as string, path as string, body as string) {
    def verb as string init strings.upper($method);
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE"], $verb)) {
        fail("unsupported method " + shown($method));
    }
    ensurePath($path);
    def headers as map of string to string init authHeaders($c);
    if ($body != "") {
        $headers["Content-Type"] = "application/json";
    }
    def o as http.Options;
    $o.tls = $c.tls;
    $o.timeoutMs = $c.timeoutMs;
    if ($verb == "GET") {
        $o.maxRetries = $c.retries;
        $o.backoffMs = 500;
    }
    def r as http.Response;
    try {
        $r = http.send($verb, $c.url + "/api/v1" + $path, $headers, $body, $o);
    } catch (e) {
        fail($verb + " " + $path + ": " + $e.message);
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail($verb + " " + $path + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    return $r;
}

/**
 * Explain a refused request: Forgejo's `message`, and the `errors` of a
 * validation failure, cut to `REASON` characters of printable ASCII.
 *
 * @param status {int} the HTTP status
 * @param statusText {string} the reason phrase
 * @param body {string} the body
 * @return {string} `HTTP <status>: <reason>`
 */
func failureText(status as int, statusText as string, body as string) {
    def text as string init "HTTP " + convert.toString($status);
    def reason as string init strings.trim($statusText);
    def doc as json.Value init json.decode("null");
    try {
        $doc = json.decode($body);
    } catch (e) {
        $doc = json.decode("null");
    }
    if (json.typeOf($doc) == "map") {
        def said as string init strings.trim(field($doc, "/message"));
        if ($said != "") {
            $reason = $said;
        }
        def extra as list of string init [];
        for (def p in items($doc, "/errors")) {
            def item as string init strings.trim(field($doc, $p));
            if ($item != "") {
                $extra[] = $item;
            }
        }
        if (len($extra) > 0) {
            $reason = $reason + " (" + strings.join($extra, "; ") + ")";
        }
    }
    if ($reason != "") {
        $text = $text + ": " + plain($reason, REASON);
    }
    return $text;
}

/**
 * Decode a reply body.
 *
 * @param body {string} the body
 * @param what {string} the request, for the error message
 * @return {json.Value} the document; JSON `null` for an empty body
 */
func decoded(body as string, what as string) {
    if (strings.trim($body) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($body);
    } catch (e) {
        fail($what + ": the reply is not JSON");
    }
    return json.decode("null");
}

/**
 * Call any endpoint.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param path {string} the path under `/api/v1`, query string included, e.g.
 *   `/repos/forgejo/forgejo/labels?limit=10`
 * @param body {string} the JSON body; "" for none
 * @return {json.Value} the reply; JSON `null` when it is empty
 * @throws {Error} kind `"forgejo"` on a bad path, a network failure or a
 *   reply that is not 2xx; the message names the status and Forgejo's reason
 * @example
 *   def labels as json.Value init forgejo.call($c, "GET", "/repos/me/app/labels", "");
 */
export func call(c as Client, method as string, path as string, body as string) {
    def r as http.Response init exchange($c, $method, $path, $body);
    return decoded($r.body, strings.upper($method) + " " + $path);
}

/**
 * GET every page of a list endpoint. Stops at the total Forgejo reports in
 * `X-Total-Count`, or at a short page when it reports none.
 *
 * @param c {Client} the client
 * @param path {string} the path under `/api/v1`, query string allowed;
 *   `page` and `limit` are added
 * @return {list of json.Value} the entries
 * @throws {Error} kind `"forgejo"` as `call`, when an answer is not a list,
 *   or past `MAX_PAGES` pages
 */
export func getAll(c as Client, path as string) {
    def out as list of json.Value init [];
    def sep as string init "?";
    if (strings.contains($path, "?")) {
        $sep = "&";
    }
    def page as int init 1;
    def more as bool init true;
    while ($more) {
        if ($page > MAX_PAGES) {
            fail("GET " + $path + ": more than " + convert.toString(MAX_PAGES) + " pages");
        }
        def url as string init $path + $sep + "limit=" + convert.toString(PAGE_SIZE) +
            "&page=" + convert.toString($page);
        def r as http.Response init exchange($c, "GET", $url, "");
        def doc as json.Value init decoded($r.body, "GET " + $path);
        if (json.typeOf($doc) != "list") {
            fail("GET " + $path + ": the reply is not a list");
        }
        def n as int init json.length($doc);
        def i as int init 0;
        while ($i < $n) {
            $out[] = json.get($doc, "/" + convert.toString($i));
            $i = $i + 1;
        }
        def total as string init strings.trim(http.header($r, "X-Total-Count"));
        if ($n == 0) {
            $more = false;
        } elseif ($total != "") {
            $more = len($out) < countOf($total);
        } else {
            $more = $n >= PAGE_SIZE;
        }
        $page = $page + 1;
    }
    return $out;
}

/**
 * The count in an `X-Total-Count` header.
 *
 * @param text {string} the header
 * @return {int} the count; 0 when it is not a number
 */
func countOf(text as string) {
    try {
        return convert.toInt($text);
    } catch (e) {
        return 0;
    }
    return 0;
}

/**
 * Build a JSON object from text fields and flags.
 *
 * @param fields {map of string to string} string members; "" values left out
 * @param flags {map of string to bool} boolean members
 * @return {string} the JSON
 */
func objectOf(fields as map of string to string, flags as map of string to bool) {
    def doc as json.Value init json.decode('{}');
    for (def key in lists.sort(maps.keys($fields))) {
        if ($fields[$key] != "") {
            $doc = json.set($doc, "/" + $key, $fields[$key]);
        }
    }
    for (def key in lists.sort(maps.keys($flags))) {
        $doc = json.set($doc, "/" + $key, $flags[$key]);
    }
    return json.encode($doc);
}

/**
 * The version of the instance.
 *
 * @param c {Client} the client
 * @return {string} e.g. `9.0.0+gitea-1.22.0`
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func version(c as Client) {
    return field(call($c, "GET", "/version", ""), "/version");
}

/**
 * An account from a reply.
 *
 * @param d {json.Value} the document
 * @param p {string} the account's pointer; "" for the root
 * @return {User} the account
 */
func userFrom(d as json.Value, p as string) {
    return User{
        id: numberAt($d, $p + "/id"),
        login: field($d, $p + "/login"),
        fullName: field($d, $p + "/full_name"),
        email: field($d, $p + "/email"),
        isAdmin: flag($d, $p + "/is_admin")
    };
}

/**
 * The account the token belongs to.
 *
 * @param c {Client} the client
 * @return {User} the account
 * @throws {Error} kind `"forgejo"` without a valid token, or as `call`
 */
export func currentUser(c as Client) {
    return userFrom(call($c, "GET", "/user", ""), "");
}

/**
 * A repository from a reply.
 *
 * @param d {json.Value} the document
 * @return {Repository} the repository
 */
func repositoryFrom(d as json.Value) {
    return Repository{
        id: numberAt($d, "/id"),
        owner: field($d, "/owner/login"),
        name: field($d, "/name"),
        fullName: field($d, "/full_name"),
        description: field($d, "/description"),
        isPrivate: flag($d, "/private"),
        isFork: flag($d, "/fork"),
        isArchived: flag($d, "/archived"),
        defaultBranch: field($d, "/default_branch"),
        htmlUrl: field($d, "/html_url"),
        cloneUrl: field($d, "/clone_url"),
        sshUrl: field($d, "/ssh_url"),
        stars: numberAt($d, "/stars_count"),
        openIssues: numberAt($d, "/open_issues_count"),
        updated: field($d, "/updated_at")
    };
}

/**
 * One repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {Repository} the repository
 * @throws {Error} kind `"forgejo"` when it does not exist or as `call`
 */
export func repository(c as Client, repo as string) {
    return repositoryFrom(call($c, "GET", repoPath($repo), ""));
}

/**
 * The repositories of a user or organization the token may see.
 *
 * @param c {Client} the client
 * @param owner {string} a user or organization
 * @return {list of Repository} the repositories
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func repositories(c as Client, owner as string) {
    def out as list of Repository init [];
    for (def d in getAll($c, "/users/" + checkOwner($owner) + "/repos")) {
        $out[] = repositoryFrom($d);
    }
    return $out;
}

/**
 * The repositories of the token's own account, including those it may
 * reach through organizations and collaboration.
 *
 * @param c {Client} the client
 * @return {list of Repository} the repositories
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func myRepositories(c as Client) {
    def out as list of Repository init [];
    for (def d in getAll($c, "/user/repos")) {
        $out[] = repositoryFrom($d);
    }
    return $out;
}

/**
 * Create an empty repository.
 *
 * @param c {Client} the client
 * @param owner {string} an organization; "" for the token's own account
 * @param name {string} the name
 * @param description {string} the description; "" for none
 * @param isPrivate {bool} whether it is private
 * @return {Repository} the new repository
 * @throws {Error} kind `"forgejo"` when the name is taken or not allowed
 */
export func createRepository(
    c as Client,
    owner as string,
    name as string,
    description as string,
    isPrivate as bool) {
    def path as string init "/user/repos";
    if ($owner != "") {
        $path = "/orgs/" + checkOwner($owner) + "/repos";
    }
    checkOwner($name);
    def body as string init objectOf(
        {"name": $name, "description": $description},
        {"private": $isPrivate});
    return repositoryFrom(call($c, "POST", $path, $body));
}

/**
 * Delete a repository, with its issues, pull requests and releases. There is
 * no undo.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @throws {Error} kind `"forgejo"` when the token may not, or as `call`
 */
export func deleteRepository(c as Client, repo as string) {
    call($c, "DELETE", repoPath($repo), "");
}

/**
 * The names under a list member.
 *
 * @param d {json.Value} the document
 * @param ptr {string} the list's pointer
 * @param key {string} the member of each entry
 * @return {list of string} the values
 */
func namesAt(d as json.Value, ptr as string, key as string) {
    def out as list of string init [];
    for (def p in items($d, $ptr)) {
        $out[] = field($d, $p + "/" + $key);
    }
    return $out;
}

/**
 * An issue from a reply.
 *
 * @param d {json.Value} the document
 * @return {Issue} the issue
 */
func issueFrom(d as json.Value) {
    return Issue{
        number: numberAt($d, "/number"),
        title: field($d, "/title"),
        body: field($d, "/body"),
        state: field($d, "/state"),
        author: field($d, "/user/login"),
        labels: namesAt($d, "/labels", "name"),
        assignees: namesAt($d, "/assignees", "login"),
        comments: numberAt($d, "/comments"),
        isPull: kindAt($d, "/pull_request") == "map",
        created: field($d, "/created_at"),
        updated: field($d, "/updated_at"),
        closed: field($d, "/closed_at"),
        htmlUrl: field($d, "/html_url")
    };
}

/**
 * Check an issue or pull request state filter.
 *
 * @param state {string} the filter
 * @return {string} the filter
 */
func checkState(state as string) {
    if (not lists.contains(["open", "closed", "all"], $state)) {
        fail("a state is open, closed or all, got " + shown($state));
    }
    return $state;
}

/**
 * The issues of a repository, newest first, without pull requests.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param state {string} `open`, `closed` or `all`
 * @return {list of Issue} the issues
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func issues(c as Client, repo as string, state as string) {
    def out as list of Issue init [];
    def path as string init repoPath($repo) + "/issues?type=issues&state=" + checkState($state);
    for (def d in getAll($c, $path)) {
        $out[] = issueFrom($d);
    }
    return $out;
}

/**
 * One issue.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} the issue number
 * @return {Issue} the issue
 * @throws {Error} kind `"forgejo"` when it does not exist or as `call`
 */
export func issue(c as Client, repo as string, number as int) {
    return issueFrom(call($c, "GET", repoPath($repo) + "/issues/" + convert.toString($number), ""));
}

/**
 * Open an issue.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param title {string} the title
 * @param body {string} the text, Markdown; "" for none
 * @return {Issue} the new issue
 * @throws {Error} kind `"forgejo"` on an empty title or as `call`
 */
export func createIssue(c as Client, repo as string, title as string, body as string) {
    if (strings.trim($title) == "") {
        fail("an issue needs a title");
    }
    def doc as string init objectOf({"title": $title, "body": $body}, {});
    return issueFrom(call($c, "POST", repoPath($repo) + "/issues", $doc));
}

/**
 * Set an issue's state.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} the issue number
 * @param state {string} `open` or `closed`
 * @return {Issue} the issue
 */
func setIssueState(c as Client, repo as string, number as int, state as string) {
    def path as string init repoPath($repo) + "/issues/" + convert.toString($number);
    return issueFrom(call($c, "PATCH", $path, objectOf({"state": $state}, {})));
}

/**
 * Close an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {Issue} the closed issue
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func closeIssue(c as Client, repo as string, number as int) {
    return setIssueState($c, $repo, $number, "closed");
}

/**
 * Reopen an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {Issue} the reopened issue
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func reopenIssue(c as Client, repo as string, number as int) {
    return setIssueState($c, $repo, $number, "open");
}

/**
 * A comment from a reply.
 *
 * @param d {json.Value} the document
 * @return {Comment} the comment
 */
func commentFrom(d as json.Value) {
    return Comment{
        id: numberAt($d, "/id"),
        author: field($d, "/user/login"),
        body: field($d, "/body"),
        created: field($d, "/created_at"),
        htmlUrl: field($d, "/html_url")
    };
}

/**
 * The comments on an issue or pull request, oldest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {list of Comment} the comments
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func comments(c as Client, repo as string, number as int) {
    def out as list of Comment init [];
    for (def d in getAll(
        $c,
        repoPath($repo) + "/issues/" + convert.toString($number) + "/comments")) {
        $out[] = commentFrom($d);
    }
    return $out;
}

/**
 * Comment on an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param body {string} the text, Markdown
 * @return {Comment} the new comment
 * @throws {Error} kind `"forgejo"` on an empty text or as `call`
 */
export func comment(c as Client, repo as string, number as int, body as string) {
    if (strings.trim($body) == "") {
        fail("a comment needs a text");
    }
    def path as string init repoPath($repo) + "/issues/" + convert.toString($number) + "/comments";
    return commentFrom(call($c, "POST", $path, objectOf({"body": $body}, {})));
}

/**
 * A pull request from a reply.
 *
 * @param d {json.Value} the document
 * @return {PullRequest} the pull request
 */
func pullFrom(d as json.Value) {
    return PullRequest{
        number: numberAt($d, "/number"),
        title: field($d, "/title"),
        body: field($d, "/body"),
        state: field($d, "/state"),
        author: field($d, "/user/login"),
        head: headOf($d),
        base: field($d, "/base/ref"),
        headSha: field($d, "/head/sha"),
        isDraft: flag($d, "/draft"),
        mergeable: flag($d, "/mergeable"),
        merged: flag($d, "/merged"),
        mergeSha: field($d, "/merge_commit_sha"),
        htmlUrl: field($d, "/html_url")
    };
}

/**
 * The head branch of a pull request. Once the branch is gone, as after a
 * merge that deleted it, `ref` is `refs/pull/<n>/head` and `label` keeps the
 * branch name.
 *
 * @param d {json.Value} the pull request
 * @return {string} the branch name
 */
func headOf(d as json.Value) {
    def ref as string init field($d, "/head/ref");
    if (strings.startsWith($ref, "refs/pull/") and field($d, "/head/label") != "") {
        return field($d, "/head/label");
    }
    return $ref;
}

/**
 * The pull requests of a repository, newest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param state {string} `open`, `closed` or `all`
 * @return {list of PullRequest} the pull requests
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func pullRequests(c as Client, repo as string, state as string) {
    def out as list of PullRequest init [];
    for (def d in getAll($c, repoPath($repo) + "/pulls?state=" + checkState($state))) {
        $out[] = pullFrom($d);
    }
    return $out;
}

/**
 * One pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {PullRequest} the pull request
 * @throws {Error} kind `"forgejo"` when it does not exist or as `call`
 */
export func pullRequest(c as Client, repo as string, number as int) {
    return pullFrom(call($c, "GET", repoPath($repo) + "/pulls/" + convert.toString($number), ""));
}

/**
 * Open a pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param head {string} the branch with the changes; `user:branch` for a fork
 * @param base {string} the branch to merge into
 * @param title {string} the title
 * @param body {string} the text, Markdown; "" for none
 * @return {PullRequest} the new pull request
 * @throws {Error} kind `"forgejo"` on an empty title or as `call`
 */
export func createPullRequest(
    c as Client,
    repo as string,
    head as string,
    base as string,
    title as string,
    body as string) {
    if (strings.trim($title) == "" or $head == "" or $base == "") {
        fail("a pull request needs a head, a base and a title");
    }
    def doc as string init objectOf(
        {"head": $head, "base": $base, "title": $title, "body": $body},
        {});
    return pullFrom(call($c, "POST", repoPath($repo) + "/pulls", $doc));
}

/**
 * Merge a pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param style {string} one of `MERGE_STYLES`
 * @param deleteBranch {bool} delete the head branch afterwards
 * @throws {Error} kind `"forgejo"` on an unknown style, when the pull
 *   request cannot be merged (HTTP 405) or its head moved (HTTP 409)
 */
export func mergePullRequest(
    c as Client,
    repo as string,
    number as int,
    style as string,
    deleteBranch as bool) {
    if (not lists.contains(MERGE_STYLES, $style)) {
        fail("a merge style is one of " + strings.join(MERGE_STYLES, ", ") + ", got " +
            shown($style));
    }
    def path as string init repoPath($repo) + "/pulls/" + convert.toString($number) + "/merge";
    call($c, "POST", $path, objectOf({"Do": $style}, {"delete_branch_after_merge": $deleteBranch}));
}

/**
 * An asset from a reply.
 *
 * @param d {json.Value} the document
 * @param p {string} the asset's pointer; "" for the root
 * @return {Asset} the asset
 */
func assetFrom(d as json.Value, p as string) {
    return Asset{
        id: numberAt($d, $p + "/id"),
        name: field($d, $p + "/name"),
        size: numberAt($d, $p + "/size"),
        downloads: numberAt($d, $p + "/download_count"),
        downloadUrl: field($d, $p + "/browser_download_url")
    };
}

/**
 * A release from a reply.
 *
 * @param d {json.Value} the document
 * @return {Release} the release
 */
func releaseFrom(d as json.Value) {
    def assets as list of Asset init [];
    for (def p in items($d, "/assets")) {
        $assets[] = assetFrom($d, $p);
    }
    return Release{
        id: numberAt($d, "/id"),
        tag: field($d, "/tag_name"),
        name: field($d, "/name"),
        body: field($d, "/body"),
        isDraft: flag($d, "/draft"),
        isPrerelease: flag($d, "/prerelease"),
        created: field($d, "/created_at"),
        published: field($d, "/published_at"),
        htmlUrl: field($d, "/html_url"),
        assets: $assets
    };
}

/**
 * The releases of a repository, newest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of Release} the releases
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func releases(c as Client, repo as string) {
    def out as list of Release init [];
    for (def d in getAll($c, repoPath($repo) + "/releases")) {
        $out[] = releaseFrom($d);
    }
    return $out;
}

/**
 * The release of a tag.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param tag {string} the tag, e.g. `1.2.0`
 * @return {Release} the release
 * @throws {Error} kind `"forgejo"` when there is none or as `call`
 */
export func release(c as Client, repo as string, tag as string) {
    return releaseFrom(call($c, "GET", tagPath($repo, $tag), ""));
}

/**
 * The path of a tag's release. The tag is one path segment: a `/` in it is
 * sent as `%2F`, which Forgejo routes to the tag, where a plain `/` is a
 * route of its own and answers 404.
 *
 * @param repo {string} `owner/name`
 * @param tag {string} the tag
 * @return {string} the path
 */
func tagPath(repo as string, tag as string) {
    segments($tag, "tag");
    return repoPath($repo) + "/releases/tags/" + uri.encode($tag);
}

/**
 * Publish a release, creating the tag at `target` when it does not exist.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param tag {string} the tag, e.g. `1.2.0`
 * @param target {string} the branch or commit to tag; "" for the default branch
 * @param name {string} the title; "" for the tag
 * @param body {string} the notes, Markdown; "" for none
 * @param isPrerelease {bool} mark it as a pre-release
 * @return {Release} the new release
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func createRelease(
    c as Client,
    repo as string,
    tag as string,
    target as string,
    name as string,
    body as string,
    isPrerelease as bool) {
    segments($tag, "tag");
    def doc as string init objectOf(
        {
            "tag_name": $tag,
            "target_commitish": $target,
            "name": $name,
            "body": $body
        },
        {"draft": false, "prerelease": $isPrerelease});
    return releaseFrom(call($c, "POST", repoPath($repo) + "/releases", $doc));
}

/**
 * Delete a release. The tag stays.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the release id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteRelease(c as Client, repo as string, id as int) {
    call($c, "DELETE", repoPath($repo) + "/releases/" + convert.toString($id), "");
}

/**
 * Attach a file to a release.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param releaseId {int} the release id
 * @param name {string} the file name
 * @param data {bytes} the content
 * @return {Asset} the new asset
 * @throws {Error} kind `"forgejo"` on a bad name, a network failure or a
 *   refusal
 */
export func uploadAsset(
    c as Client,
    repo as string,
    releaseId as int,
    name as string,
    data as bytes) {
    if ($name == "" or strings.contains($name, "/") or regex.matches("[\\x00-\\x1f\\x7f]", $name)) {
        fail("an asset name holds no / or control characters, got " + shown($name));
    }
    def path as string init repoPath($repo) + "/releases/" + convert.toString($releaseId) +
        "/assets?name=" + uri.encode($name);
    def built as multipart.Built init multipart.build([
        multipart.file("attachment", $name, "application/octet-stream", $data)
    ]);
    def headers as map of string to string init authHeaders($c);
    $headers["Content-Type"] = $built.contentType;
    def r as http.Response;
    try {
        $r = http.requestRawBodyTls(
            "POST",
            $c.url + "/api/v1" + $path,
            $headers,
            $built.body,
            idleMs($c),
            0,
            $c.tls);
    } catch (e) {
        fail("POST " + $path + ": " + $e.message);
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail("POST " + $path + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    return assetFrom(decoded($r.body, "POST " + $path), "");
}

/**
 * GET bytes from a URL on the instance, with the token.
 *
 * @param c {Client} the client
 * @param url {string} the absolute URL
 * @param maxBytes {int} the largest reply accepted; 0 for 64 MiB, negative
 *   for no limit
 * @return {bytes} the body
 */
func fetchBytes(c as Client, url as string, maxBytes as int) {
    def headers as map of string to string init authHeaders($c);
    $headers["Accept"] = "*/*";
    def r as http.BytesResponse;
    try {
        $r = http.requestWithBytes("GET", $url, $headers, "", idleMs($c), $maxBytes, $c.tls);
    } catch (e) {
        fail("GET " + $url + ": " + $e.message);
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail(
            "GET " + $url + ": " +
                failureText($r.status, $r.statusText, convert.stringFromBytes($r.body, "utf-8")));
    }
    return $r.body;
}

/**
 * Download a release asset. The token is only sent to the instance itself:
 * an asset whose URL points elsewhere is refused.
 *
 * @param c {Client} the client
 * @param asset {Asset} the asset, from a `Release`
 * @param maxBytes {int} the largest file accepted; 0 for 64 MiB, negative
 *   for no limit
 * @return {bytes} the content
 * @throws {Error} kind `"forgejo"` on a foreign URL, a network failure or a
 *   file over `maxBytes`
 */
export func downloadAsset(c as Client, asset as Asset, maxBytes as int) {
    if (not strings.startsWith($asset.downloadUrl, $c.url + "/")) {
        fail("the asset " + shown($asset.name) + " is not on " + $c.url + ": " +
            shown($asset.downloadUrl));
    }
    return fetchBytes($c, $asset.downloadUrl, $maxBytes);
}

/**
 * The branches of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of Branch} the branches
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func branches(c as Client, repo as string) {
    def out as list of Branch init [];
    for (def d in getAll($c, repoPath($repo) + "/branches")) {
        $out[] = Branch{
            name: field($d, "/name"),
            sha: field($d, "/commit/id"),
            isProtected: flag($d, "/protected")
        };
    }
    return $out;
}

/**
 * The tags of a repository, newest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of Tag} the tags
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func tags(c as Client, repo as string) {
    def out as list of Tag init [];
    for (def d in getAll($c, repoPath($repo) + "/tags")) {
        $out[] = Tag{
            name: field($d, "/name"),
            sha: field($d, "/commit/sha"),
            message: field($d, "/message")
        };
    }
    return $out;
}

/**
 * Read a file from a repository. A file kept in Git LFS comes as its
 * content, not as the pointer.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param path {string} the file, e.g. `docs/index.md`
 * @param ref {string} a branch, tag or commit; "" for the default branch
 * @return {bytes} the content
 * @throws {Error} kind `"forgejo"` when it does not exist, on a network
 *   failure, or for a file over 64 MiB
 */
export func readFile(c as Client, repo as string, path as string, ref as string) {
    def url as string init $c.url + "/api/v1" + repoPath($repo) + "/media/" +
        segments($path, "file path");
    if ($ref != "") {
        $url = $url + "?ref=" + uri.encode($ref);
    }
    return fetchBytes($c, $url, 0);
}

/**
 * Create or replace a file with a commit of its own.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param path {string} the file, e.g. `data/version.txt`
 * @param data {bytes} the new content
 * @param message {string} the commit message
 * @param branch {string} the branch to commit to; "" for the default branch
 * @return {string} the new commit's SHA
 * @throws {Error} kind `"forgejo"` on an empty message, a bad path or as
 *   `call`
 */
export func writeFile(
    c as Client,
    repo as string,
    path as string,
    data as bytes,
    message as string,
    branch as string) {
    if (strings.trim($message) == "") {
        fail("a commit needs a message");
    }
    def file as string init repoPath($repo) + "/contents/" + segments($path, "file path");
    def query as string init "";
    if ($branch != "") {
        $query = "?ref=" + uri.encode($branch);
    }
    # The file's blob SHA, which replacing it requires; none means create.
    def sha as string init "";
    try {
        $sha = field(call($c, "GET", $file + $query, ""), "/sha");
    } catch (e) {
        if (not strings.startsWith($e.message, "forgejo: GET " + $file + $query + ": HTTP 404")) {
            throw $e;
        }
    }
    def fields as map of string to string init {
        "content": encoding.toText($data, "base64"),
        "message": $message,
        "branch": $branch,
        "sha": $sha
    };
    def method as string init "POST";
    if ($sha != "") {
        $method = "PUT";
    }
    return field(call($c, $method, $file, objectOf($fields, {})), "/commit/sha");
}

/**
 * A JSON list of strings, for a request body.
 *
 * @param names {list of string} the strings
 * @return {json.Value} the list
 */
func stringList(names as list of string) {
    return json.decode(json.encode($names));
}

/**
 * The path of an issue or pull request.
 *
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {string} `/repos/owner/name/issues/<n>`
 */
func issuePath(repo as string, number as int) {
    return repoPath($repo) + "/issues/" + convert.toString($number);
}

# The states a commit status can have.
def const STATUS_STATES as list of string init [
    "pending",
    "success",
    "error",
    "failure",
    "warning"
];

/**
 * A commit status from a reply.
 *
 * @param d {json.Value} the reply
 * @param p {string} the status's pointer; "" for the root
 * @return {CommitStatus} the status
 */
func statusFrom(d as json.Value, p as string) {
    return CommitStatus{
        context: field($d, $p + "/context"),
        state: field($d, $p + "/status"),
        description: field($d, $p + "/description"),
        targetUrl: field($d, $p + "/target_url"),
        creator: field($d, $p + "/creator/login"),
        created: field($d, $p + "/created_at")
    };
}

/**
 * Set a status on a commit, as a CI system reports a check.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param sha {string} the commit SHA
 * @param state {string} `pending`, `success`, `error`, `failure` or `warning`
 * @param context {string} which check it is, e.g. `ci/build`
 * @param description {string} a short text; "" for none
 * @param targetUrl {string} where the details are; "" for none
 * @return {CommitStatus} the status
 * @throws {Error} kind `"forgejo"` on another state, a bad SHA, or as `call`
 * @example
 *   forgejo.setCommitStatus($c, "me/app", $sha, "success", "ci/build", "built in 42 s", $logUrl);
 */
export func setCommitStatus(
    c as Client,
    repo as string,
    sha as string,
    state as string,
    context as string,
    description as string,
    targetUrl as string) {
    if (not lists.contains(STATUS_STATES, $state)) {
        fail("a commit status is one of " + strings.join(STATUS_STATES, ", ") + ", got " +
            shown($state));
    }
    def doc as string init objectOf(
        {
            "state": $state,
            "context": $context,
            "description": $description,
            "target_url": $targetUrl
        },
        {});
    def path as string init repoPath($repo) + "/statuses/" + segments($sha, "commit");
    return statusFrom(call($c, "POST", $path, $doc), "");
}

/**
 * The statuses set on a commit, newest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param ref {string} a commit SHA, branch or tag
 * @return {list of CommitStatus} the statuses
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func commitStatuses(c as Client, repo as string, ref as string) {
    segments($ref, "ref");
    def out as list of CommitStatus init [];
    def path as string init repoPath($repo) + "/commits/" + uri.encode($ref) + "/statuses";
    for (def d in getAll($c, $path)) {
        $out[] = statusFrom($d, "");
    }
    return $out;
}

/**
 * The combined status of a commit: the latest status per context, and the
 * worst of them.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param ref {string} a commit SHA, branch or tag
 * @return {CombinedStatus} the combined status
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func combinedStatus(c as Client, repo as string, ref as string) {
    segments($ref, "ref");
    def d as json.Value init call(
        $c,
        "GET",
        repoPath($repo) + "/commits/" + uri.encode($ref) + "/status",
        "");
    def statuses as list of CommitStatus init [];
    for (def p in items($d, "/statuses")) {
        $statuses[] = statusFrom($d, $p);
    }
    return CombinedStatus{state: field($d, "/state"), statuses: $statuses};
}

/**
 * A commit from a reply.
 *
 * @param d {json.Value} the reply
 * @return {Commit} the commit
 */
func commitFrom(d as json.Value) {
    return Commit{
        sha: field($d, "/sha"),
        message: field($d, "/commit/message"),
        author: field($d, "/commit/author/name"),
        authorEmail: field($d, "/commit/author/email"),
        date: field($d, "/commit/author/date"),
        htmlUrl: field($d, "/html_url")
    };
}

/**
 * The commits reachable from a ref, newest first, without their file
 * lists.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param ref {string} a branch, tag or commit; "" for the default branch
 * @param path {string} only commits that touch this file or directory; ""
 *   for all
 * @return {list of Commit} the commits
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func commits(c as Client, repo as string, ref as string, path as string) {
    def query as string init repoPath($repo) + "/commits?stat=false&verification=false&files=false";
    if ($ref != "") {
        $query = $query + "&sha=" + uri.encode($ref);
    }
    if ($path != "") {
        segments($path, "file path");
        $query = $query + "&path=" + uri.encode($path);
    }
    def out as list of Commit init [];
    for (def d in getAll($c, $query)) {
        $out[] = commitFrom($d);
    }
    return $out;
}

/**
 * One commit.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param sha {string} the commit SHA, or a branch or tag
 * @return {Commit} the commit
 * @throws {Error} kind `"forgejo"` when there is none, or as `call`
 */
export func commit(c as Client, repo as string, sha as string) {
    def path as string init repoPath($repo) + "/git/commits/" +
        uri.encode(checked($sha, "commit")) +
        "?stat=false&verification=false&files=false";
    return commitFrom(call($c, "GET", $path, ""));
}

/**
 * Run a Forgejo Actions workflow that has a `workflow_dispatch` trigger.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param workflow {string} the workflow file, e.g. `release.yml`
 * @param ref {string} the branch or tag to run it on
 * @param inputs {map of string to string} the workflow's inputs; `{}` for none
 * @return {int} the run's id; 0 when the instance does not report it
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func dispatchWorkflow(
    c as Client,
    repo as string,
    workflow as string,
    ref as string,
    inputs as map of string to string) {
    if ($ref == "") {
        fail("a workflow runs on a ref");
    }
    def doc as json.Value init json.decode('{"return_run_info":true}');
    $doc = json.set($doc, "/ref", $ref);
    $doc = json.set($doc, "/inputs", json.decode(objectOf($inputs, {})));
    def path as string init repoPath($repo) + "/actions/workflows/" +
        uri.encode(checked($workflow, "workflow")) +
        "/dispatches";
    return numberAt(call($c, "POST", $path, json.encode($doc)), "/id");
}

/**
 * Refuse a secret or variable name Forgejo would not take.
 *
 * @param name {string} the name
 * @return {string} the name
 */
func checkVariable(name as string) {
    if (not regex.matches("^[A-Za-z_][A-Za-z0-9_]*$", $name) or
        strings.startsWith(strings.upper($name), "GITHUB_") or
        strings.startsWith(strings.upper($name), "GITEA_") or
        strings.startsWith(strings.upper($name), "FORGEJO_")) {
        fail("a secret or variable name is letters, digits and _, not starting with a digit, " +
            "FORGEJO_, GITEA_ or GITHUB_, got " + shown($name));
    }
    return $name;
}

/**
 * Create or replace an Actions secret of a repository. Its value cannot be
 * read back.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the secret's name, e.g. `DEPLOY_KEY`
 * @param value {string} the value
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func setSecret(c as Client, repo as string, name as string, value as string) {
    def path as string init repoPath($repo) + "/actions/secrets/" + checkVariable($name);
    call($c, "PUT", $path, objectOf({"data": $value}, {}));
}

/**
 * Delete an Actions secret of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the secret's name
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteSecret(c as Client, repo as string, name as string) {
    call($c, "DELETE", repoPath($repo) + "/actions/secrets/" + checkVariable($name), "");
}

/**
 * The Actions variables of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {map of string to string} each variable's value by its name
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func variables(c as Client, repo as string) {
    def out as map of string to string init {};
    for (def d in getAll($c, repoPath($repo) + "/actions/variables")) {
        $out[field($d, "/name")] = field($d, "/data");
    }
    return $out;
}

/**
 * Create or replace an Actions variable of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the variable's name
 * @param value {string} the value
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func setVariable(c as Client, repo as string, name as string, value as string) {
    def path as string init repoPath($repo) + "/actions/variables/" + checkVariable($name);
    try {
        call($c, "PUT", $path, objectOf({"name": $name, "value": $value}, {}));
    } catch (e) {
        if (not strings.startsWith($e.message, "forgejo: PUT " + $path + ": HTTP 404")) {
            throw $e;
        }
        call($c, "POST", $path, objectOf({"value": $value}, {}));
    }
}

/**
 * Delete an Actions variable of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the variable's name
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteVariable(c as Client, repo as string, name as string) {
    call($c, "DELETE", repoPath($repo) + "/actions/variables/" + checkVariable($name), "");
}

/**
 * Change an issue's title or text.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} the issue or pull request number
 * @param title {string} the new title; "" to keep it
 * @param body {string} the new text; "" to keep it
 * @return {Issue} the issue
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func editIssue(c as Client, repo as string, number as int, title as string, body as string) {
    def doc as string init objectOf({"title": $title, "body": $body}, {});
    return issueFrom(call($c, "PATCH", issuePath($repo, $number), $doc));
}

/**
 * Set who is assigned to an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param names {list of string} the user names; `[]` for nobody
 * @return {Issue} the issue
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func setAssignees(c as Client, repo as string, number as int, names as list of string) {
    for (def name in $names) {
        checkOwner($name);
    }
    def doc as json.Value init json.set(json.decode('{}'), "/assignees", stringList($names));
    return issueFrom(call($c, "PATCH", issuePath($repo, $number), json.encode($doc)));
}

/**
 * Put an issue or pull request in a milestone.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param milestoneId {int} the milestone's id; 0 for none
 * @return {Issue} the issue
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func setMilestone(c as Client, repo as string, number as int, milestoneId as int) {
    def doc as json.Value init json.set(json.decode('{}'), "/milestone", $milestoneId);
    return issueFrom(call($c, "PATCH", issuePath($repo, $number), json.encode($doc)));
}

/**
 * Change a pull request's title or text.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param title {string} the new title; "" to keep it
 * @param body {string} the new text; "" to keep it
 * @return {PullRequest} the pull request
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func editPullRequest(
    c as Client,
    repo as string,
    number as int,
    title as string,
    body as string) {
    def doc as string init objectOf({"title": $title, "body": $body}, {});
    def path as string init repoPath($repo) + "/pulls/" + convert.toString($number);
    return pullFrom(call($c, "PATCH", $path, $doc));
}

/**
 * Change a release's title or notes.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the release id
 * @param name {string} the new title; "" to keep it
 * @param body {string} the new notes; "" to keep them
 * @return {Release} the release
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func editRelease(c as Client, repo as string, id as int, name as string, body as string) {
    def doc as string init objectOf({"name": $name, "body": $body}, {});
    def path as string init repoPath($repo) + "/releases/" + convert.toString($id);
    return releaseFrom(call($c, "PATCH", $path, $doc));
}

/**
 * Change a comment's text.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the comment id
 * @param body {string} the new text
 * @return {Comment} the comment
 * @throws {Error} kind `"forgejo"` on an empty text, or as `call`
 */
export func editComment(c as Client, repo as string, id as int, body as string) {
    if (strings.trim($body) == "") {
        fail("a comment needs a text");
    }
    def path as string init repoPath($repo) + "/issues/comments/" + convert.toString($id);
    return commentFrom(call($c, "PATCH", $path, objectOf({"body": $body}, {})));
}

/**
 * Delete a comment.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the comment id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteComment(c as Client, repo as string, id as int) {
    call($c, "DELETE", repoPath($repo) + "/issues/comments/" + convert.toString($id), "");
}

/**
 * Change a repository's description and website.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param description {string} the new description; "" to keep it
 * @param website {string} the new website; "" to keep it
 * @return {Repository} the repository
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func editRepository(c as Client, repo as string, description as string, website as string) {
    def doc as string init objectOf({"description": $description, "website": $website}, {});
    return repositoryFrom(call($c, "PATCH", repoPath($repo), $doc));
}

/**
 * Archive a repository, or bring it back. An archived one is read-only.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param archived {bool} whether it is archived
 * @return {Repository} the repository
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func setArchived(c as Client, repo as string, archived as bool) {
    def doc as string init objectOf({}, {"archived": $archived});
    return repositoryFrom(call($c, "PATCH", repoPath($repo), $doc));
}

/**
 * Change a repository's default branch.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param branch {string} an existing branch
 * @return {Repository} the repository
 * @throws {Error} kind `"forgejo"` on an empty name, or as `call`
 */
export func setDefaultBranch(c as Client, repo as string, branch as string) {
    segments($branch, "branch");
    return repositoryFrom(call(
        $c,
        "PATCH",
        repoPath($repo),
        objectOf({"default_branch": $branch}, {})));
}

/**
 * A label from a reply.
 *
 * @param d {json.Value} the reply
 * @param p {string} the label's pointer; "" for the root
 * @return {Label} the label
 */
func labelFrom(d as json.Value, p as string) {
    # Forgejo answers `ee0701`; `createLabel` takes `#ee0701`.
    def color as string init field($d, $p + "/color");
    if ($color != "" and not strings.startsWith($color, "#")) {
        $color = "#" + $color;
    }
    return Label{
        id: numberAt($d, $p + "/id"),
        name: field($d, $p + "/name"),
        color: $color,
        description: field($d, $p + "/description"),
        exclusive: flag($d, $p + "/exclusive")
    };
}

/**
 * The labels of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of Label} the labels
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func labels(c as Client, repo as string) {
    def out as list of Label init [];
    for (def d in getAll($c, repoPath($repo) + "/labels")) {
        $out[] = labelFrom($d, "");
    }
    return $out;
}

/**
 * Create a label.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the name; `scope/name` makes a scoped label
 * @param color {string} the colour, e.g. `#ee0701`
 * @param description {string} the description; "" for none
 * @return {Label} the new label
 * @throws {Error} kind `"forgejo"` on an empty name or a colour that is not
 *   `#rrggbb`, or as `call`
 */
export func createLabel(
    c as Client,
    repo as string,
    name as string,
    color as string,
    description as string) {
    if (strings.trim($name) == "") {
        fail("a label needs a name");
    }
    if (not regex.matches("^#[0-9A-Fa-f]\{6\}$", $color)) {
        fail("a label colour is #rrggbb, got " + shown($color));
    }
    def doc as string init objectOf(
        {"name": $name, "color": $color, "description": $description},
        {});
    return labelFrom(call($c, "POST", repoPath($repo) + "/labels", $doc), "");
}

/**
 * Delete a label, from the repository and every issue that has it.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the label id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteLabel(c as Client, repo as string, id as int) {
    call($c, "DELETE", repoPath($repo) + "/labels/" + convert.toString($id), "");
}

/**
 * Send an issue's label names.
 *
 * @param c {Client} the client
 * @param method {string} `PUT` to replace, `POST` to add
 * @param repo {string} `owner/name`
 * @param number {int} the issue number
 * @param names {list of string} label names
 * @return {list of Label} the issue's labels now
 */
func sendLabels(
    c as Client,
    method as string,
    repo as string,
    number as int,
    names as list of string) {
    def doc as json.Value init json.set(json.decode('{}'), "/labels", stringList($names));
    def d as json.Value init call(
        $c,
        $method,
        issuePath($repo, $number) + "/labels",
        json.encode($doc));
    def out as list of Label init [];
    for (def p in items($d, "")) {
        $out[] = labelFrom($d, $p);
    }
    return $out;
}

/**
 * Replace the labels of an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param names {list of string} label names; `[]` for none
 * @return {list of Label} its labels now
 * @throws {Error} kind `"forgejo"` when a label does not exist, or as `call`
 */
export func setIssueLabels(c as Client, repo as string, number as int, names as list of string) {
    return sendLabels($c, "PUT", $repo, $number, $names);
}

/**
 * Add labels to an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param names {list of string} label names
 * @return {list of Label} its labels now
 * @throws {Error} kind `"forgejo"` when a label does not exist, or as `call`
 */
export func addIssueLabels(c as Client, repo as string, number as int, names as list of string) {
    return sendLabels($c, "POST", $repo, $number, $names);
}

/**
 * Take a label off an issue or pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param name {string} the label name
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func removeIssueLabel(c as Client, repo as string, number as int, name as string) {
    if (strings.trim($name) == "") {
        fail("a label needs a name");
    }
    call($c, "DELETE", issuePath($repo, $number) + "/labels/" + uri.encode($name), "");
}

/**
 * A milestone from a reply.
 *
 * @param d {json.Value} the reply
 * @param p {string} the milestone's pointer; "" for the root
 * @return {Milestone} the milestone
 */
func milestoneFrom(d as json.Value, p as string) {
    return Milestone{
        id: numberAt($d, $p + "/id"),
        title: field($d, $p + "/title"),
        description: field($d, $p + "/description"),
        state: field($d, $p + "/state"),
        dueOn: field($d, $p + "/due_on"),
        openIssues: numberAt($d, $p + "/open_issues"),
        closedIssues: numberAt($d, $p + "/closed_issues")
    };
}

/**
 * The milestones of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param state {string} `open`, `closed` or `all`
 * @return {list of Milestone} the milestones
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func milestones(c as Client, repo as string, state as string) {
    def out as list of Milestone init [];
    for (def d in getAll($c, repoPath($repo) + "/milestones?state=" + checkState($state))) {
        $out[] = milestoneFrom($d, "");
    }
    return $out;
}

/**
 * Create a milestone.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param title {string} the title
 * @param description {string} the description; "" for none
 * @param dueOn {string} the due date, RFC 3339 (`2026-12-31T00:00:00Z`); ""
 *   for none
 * @return {Milestone} the new milestone
 * @throws {Error} kind `"forgejo"` on an empty title, or as `call`
 */
export func createMilestone(
    c as Client,
    repo as string,
    title as string,
    description as string,
    dueOn as string) {
    if (strings.trim($title) == "") {
        fail("a milestone needs a title");
    }
    def doc as string init objectOf(
        {
            "title": $title,
            "description": $description,
            "due_on": $dueOn
        },
        {});
    return milestoneFrom(call($c, "POST", repoPath($repo) + "/milestones", $doc), "");
}

/**
 * Close a milestone, or open it again.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the milestone id
 * @param closed {bool} whether it is closed
 * @return {Milestone} the milestone
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func setMilestoneClosed(c as Client, repo as string, id as int, closed as bool) {
    def state as string init "open";
    if ($closed) {
        $state = "closed";
    }
    def path as string init repoPath($repo) + "/milestones/" + convert.toString($id);
    return milestoneFrom(call($c, "PATCH", $path, objectOf({"state": $state}, {})), "");
}

/**
 * Delete a milestone. Its issues stay, without a milestone.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the milestone id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteMilestone(c as Client, repo as string, id as int) {
    call($c, "DELETE", repoPath($repo) + "/milestones/" + convert.toString($id), "");
}

/**
 * A branch from a reply.
 *
 * @param d {json.Value} the reply
 * @return {Branch} the branch
 */
func branchFrom(d as json.Value) {
    return Branch{
        name: field($d, "/name"),
        sha: field($d, "/commit/id"),
        isProtected: flag($d, "/protected")
    };
}

/**
 * Create a branch.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the new branch
 * @param from {string} the branch, tag or commit it starts at; "" for the
 *   default branch
 * @return {Branch} the new branch
 * @throws {Error} kind `"forgejo"` on a bad name, or when it exists (HTTP 409)
 */
export func createBranch(c as Client, repo as string, name as string, from as string) {
    segments($name, "branch");
    def doc as string init objectOf({"new_branch_name": $name, "old_ref_name": $from}, {});
    return branchFrom(call($c, "POST", repoPath($repo) + "/branches", $doc));
}

/**
 * Delete a branch.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the branch
 * @throws {Error} kind `"forgejo"` when it is protected or the default
 *   branch, or as `call`
 */
export func deleteBranch(c as Client, repo as string, name as string) {
    call($c, "DELETE", repoPath($repo) + "/branches/" + segments($name, "branch"), "");
}

/**
 * Create a tag.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the tag, e.g. `1.2.0`
 * @param target {string} the branch or commit to tag; "" for the default
 *   branch
 * @param message {string} the annotation; "" for a lightweight tag
 * @return {Tag} the new tag
 * @throws {Error} kind `"forgejo"` on a bad name, or when it exists (HTTP 409)
 */
export func createTag(
    c as Client,
    repo as string,
    name as string,
    target as string,
    message as string) {
    segments($name, "tag");
    def doc as string init objectOf(
        {"tag_name": $name, "target": $target, "message": $message},
        {});
    def d as json.Value init call($c, "POST", repoPath($repo) + "/tags", $doc);
    return Tag{
        name: field($d, "/name"),
        sha: field($d, "/commit/sha"),
        message: field($d, "/message")
    };
}

/**
 * Delete a tag. A release of it stays, as a draft without its tag.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the tag
 * @throws {Error} kind `"forgejo"` when it is protected, or as `call`
 */
export func deleteTag(c as Client, repo as string, name as string) {
    segments($name, "tag");
    call($c, "DELETE", repoPath($repo) + "/tags/" + uri.encode($name), "");
}

/**
 * Delete a file with a commit of its own.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param path {string} the file
 * @param message {string} the commit message
 * @param branch {string} the branch to commit to; "" for the default branch
 * @return {string} the new commit's SHA
 * @throws {Error} kind `"forgejo"` on an empty message, when the file does
 *   not exist, or as `call`
 */
export func deleteFile(
    c as Client,
    repo as string,
    path as string,
    message as string,
    branch as string) {
    if (strings.trim($message) == "") {
        fail("a commit needs a message");
    }
    def file as string init repoPath($repo) + "/contents/" + segments($path, "file path");
    def query as string init "";
    if ($branch != "") {
        $query = "?ref=" + uri.encode($branch);
    }
    def sha as string init field(call($c, "GET", $file + $query, ""), "/sha");
    if ($sha == "") {
        fail("DELETE " + $file + ": " + shown($path) + " is not a file");
    }
    def doc as string init objectOf({"message": $message, "branch": $branch, "sha": $sha}, {});
    return field(call($c, "DELETE", $file, $doc), "/commit/sha");
}

/**
 * The entries of a directory in a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param path {string} the directory; "" for the root
 * @param ref {string} a branch, tag or commit; "" for the default branch
 * @return {list of Entry} the entries
 * @throws {Error} kind `"forgejo"` when it does not exist or is a file, or
 *   as `call`
 */
export func listDirectory(c as Client, repo as string, path as string, ref as string) {
    def url as string init repoPath($repo) + "/contents";
    if ($path != "") {
        $url = $url + "/" + segments($path, "directory");
    }
    if ($ref != "") {
        $url = $url + "?ref=" + uri.encode($ref);
    }
    def d as json.Value init call($c, "GET", $url, "");
    if (kindAt($d, "") != "list") {
        fail("GET " + $url + ": " + shown($path) + " is not a directory");
    }
    def out as list of Entry init [];
    for (def p in items($d, "")) {
        $out[] = Entry{
            name: field($d, $p + "/name"),
            path: field($d, $p + "/path"),
            type: field($d, $p + "/type"),
            size: numberAt($d, $p + "/size"),
            sha: field($d, $p + "/sha")
        };
    }
    return $out;
}

/**
 * The path of a pull request.
 *
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {string} `/repos/owner/name/pulls/<n>`
 */
func pullPath(repo as string, number as int) {
    return repoPath($repo) + "/pulls/" + convert.toString($number);
}

/**
 * A review from a reply.
 *
 * @param d {json.Value} the reply
 * @param p {string} the review's pointer; "" for the root
 * @return {Review} the review
 */
func reviewFrom(d as json.Value, p as string) {
    return Review{
        id: numberAt($d, $p + "/id"),
        author: field($d, $p + "/user/login"),
        state: field($d, $p + "/state"),
        body: field($d, $p + "/body"),
        commitId: field($d, $p + "/commit_id"),
        submitted: field($d, $p + "/submitted_at")
    };
}

# What a review can say.
def const REVIEW_EVENTS as list of string init ["APPROVED", "REQUEST_CHANGES", "COMMENT"];

/**
 * Review a pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param event {string} `APPROVED`, `REQUEST_CHANGES` or `COMMENT`
 * @param body {string} the text; "" for none, which `REQUEST_CHANGES` and
 *   `COMMENT` do not allow
 * @return {Review} the review
 * @throws {Error} kind `"forgejo"` on another event, or as `call`
 */
export func reviewPullRequest(
    c as Client,
    repo as string,
    number as int,
    event as string,
    body as string) {
    if (not lists.contains(REVIEW_EVENTS, $event)) {
        fail("a review is APPROVED, REQUEST_CHANGES or COMMENT, got " + shown($event));
    }
    if ($event != "APPROVED" and strings.trim($body) == "") {
        fail("a " + $event + " review needs a text");
    }
    def doc as string init objectOf({"event": $event, "body": $body}, {});
    return reviewFrom(call($c, "POST", pullPath($repo, $number) + "/reviews", $doc), "");
}

/**
 * The reviews of a pull request, oldest first.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {list of Review} the reviews
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func reviews(c as Client, repo as string, number as int) {
    def out as list of Review init [];
    for (def d in getAll($c, pullPath($repo, $number) + "/reviews")) {
        $out[] = reviewFrom($d, "");
    }
    return $out;
}

/**
 * Ask users to review a pull request.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @param names {list of string} the user names
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func requestReviewers(c as Client, repo as string, number as int, names as list of string) {
    if (len($names) == 0) {
        fail("a review request names a reviewer");
    }
    for (def name in $names) {
        checkOwner($name);
    }
    def doc as json.Value init json.set(json.decode('{}'), "/reviewers", stringList($names));
    call($c, "POST", pullPath($repo, $number) + "/requested_reviewers", json.encode($doc));
}

/**
 * The files a pull request changes.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param number {int} its number
 * @return {list of ChangedFile} the files
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func pullRequestFiles(c as Client, repo as string, number as int) {
    def out as list of ChangedFile init [];
    for (def d in getAll($c, pullPath($repo, $number) + "/files")) {
        $out[] = ChangedFile{
            filename: field($d, "/filename"),
            status: field($d, "/status"),
            additions: numberAt($d, "/additions"),
            deletions: numberAt($d, "/deletions"),
            previousFilename: field($d, "/previous_filename")
        };
    }
    return $out;
}

/**
 * A webhook from a reply.
 *
 * @param d {json.Value} the reply
 * @return {Hook} the hook
 */
func hookFrom(d as json.Value) {
    def events as list of string init [];
    for (def p in items($d, "/events")) {
        $events[] = field($d, $p);
    }
    return Hook{
        id: numberAt($d, "/id"),
        type: field($d, "/type"),
        url: field($d, "/config/url"),
        events: $events,
        active: flag($d, "/active")
    };
}

/**
 * The webhooks of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of Hook} the webhooks
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func hooks(c as Client, repo as string) {
    def out as list of Hook init [];
    for (def d in getAll($c, repoPath($repo) + "/hooks")) {
        $out[] = hookFrom($d);
    }
    return $out;
}

/**
 * Add a Forgejo webhook that posts JSON to a URL.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param url {string} where to post, `https://...`
 * @param secret {string} the secret the payload is signed with
 *   (`X-Forgejo-Signature`); "" for none
 * @param events {list of string} the events, e.g. `["push", "pull_request"]`
 * @return {Hook} the new webhook
 * @throws {Error} kind `"forgejo"` on a URL that is not http(s), no events,
 *   or as `call`
 */
export func createHook(
    c as Client,
    repo as string,
    url as string,
    secret as string,
    events as list of string) {
    if (not regex.matches("^https?://[^\\s]+$", $url)) {
        fail("a webhook URL is http:// or https://, got " + shown($url));
    }
    if (len($events) == 0) {
        fail("a webhook fires on at least one event");
    }
    def doc as json.Value init json.decode('{"type":"forgejo","active":true}');
    $doc = json.set(
        $doc,
        "/config",
        json.decode(objectOf({"url": $url, "content_type": "json", "secret": $secret}, {})));
    $doc = json.set($doc, "/events", stringList($events));
    return hookFrom(call($c, "POST", repoPath($repo) + "/hooks", json.encode($doc)));
}

/**
 * Delete a webhook.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param id {int} the hook id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteHook(c as Client, repo as string, id as int) {
    call($c, "DELETE", repoPath($repo) + "/hooks/" + convert.toString($id), "");
}

/**
 * The collaborators of a repository.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {list of User} the collaborators
 * @throws {Error} kind `"forgejo"` as `getAll`
 */
export func collaborators(c as Client, repo as string) {
    def out as list of User init [];
    for (def d in getAll($c, repoPath($repo) + "/collaborators")) {
        $out[] = userFrom($d, "");
    }
    return $out;
}

/**
 * Add a collaborator, or change what one may do.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the user
 * @param permission {string} `read`, `write` or `admin`
 * @throws {Error} kind `"forgejo"` on another permission, or as `call`
 */
export func addCollaborator(c as Client, repo as string, name as string, permission as string) {
    if (not lists.contains(["read", "write", "admin"], $permission)) {
        fail("a permission is read, write or admin, got " + shown($permission));
    }
    def path as string init repoPath($repo) + "/collaborators/" + checkOwner($name);
    call($c, "PUT", $path, objectOf({"permission": $permission}, {}));
}

/**
 * Remove a collaborator.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param name {string} the user
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func removeCollaborator(c as Client, repo as string, name as string) {
    call($c, "DELETE", repoPath($repo) + "/collaborators/" + checkOwner($name), "");
}

/**
 * Fork a repository. Forgejo copies it in the background; the fork may be
 * empty for a moment.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name` to fork
 * @param organization {string} the organization to fork into; "" for the
 *   token's account
 * @param name {string} the fork's name; "" for the same name
 * @return {Repository} the fork
 * @throws {Error} kind `"forgejo"` on a bad name, or as `call`
 */
export func forkRepository(c as Client, repo as string, organization as string, name as string) {
    if ($organization != "") {
        checkOwner($organization);
    }
    if ($name != "") {
        checkOwner($name);
    }
    def doc as string init objectOf({"organization": $organization, "name": $name}, {});
    return repositoryFrom(call($c, "POST", repoPath($repo) + "/forks", $doc));
}

/**
 * Search the repositories the token may see by name and description.
 *
 * @param c {Client} the client
 * @param query {string} the words to look for
 * @return {list of Repository} the matches, best first
 * @throws {Error} kind `"forgejo"` on an empty query, past `MAX_PAGES`
 *   pages, or as `call`
 */
export func searchRepositories(c as Client, query as string) {
    if (strings.trim($query) == "") {
        fail("a search needs a query");
    }
    def out as list of Repository init [];
    def page as int init 1;
    def more as bool init true;
    while ($more) {
        if ($page > MAX_PAGES) {
            fail("GET /repos/search: more than " + convert.toString(MAX_PAGES) + " pages");
        }
        def path as string init "/repos/search?includeDesc=true&q=" + uri.encode($query) +
            "&limit=" +
            convert.toString(PAGE_SIZE) + "&page=" + convert.toString($page);
        def r as http.Response init exchange($c, "GET", $path, "");
        def d as json.Value init decoded($r.body, "GET /repos/search");
        def found as list of string init items($d, "/data");
        for (def p in $found) {
            $out[] = repositoryFrom(json.get($d, $p));
        }
        def total as string init strings.trim(http.header($r, "X-Total-Count"));
        if (len($found) == 0) {
            $more = false;
        } elseif ($total != "") {
            $more = len($out) < countOf($total);
        } else {
            $more = len($found) >= PAGE_SIZE;
        }
        $page = $page + 1;
    }
    return $out;
}

/**
 * The newest release that is neither a draft nor a pre-release.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @return {Release} the release
 * @throws {Error} kind `"forgejo"` when there is none (HTTP 404), or as `call`
 */
export func latestRelease(c as Client, repo as string) {
    return releaseFrom(call($c, "GET", repoPath($repo) + "/releases/latest", ""));
}

/**
 * Delete a file attached to a release.
 *
 * @param c {Client} the client
 * @param repo {string} `owner/name`
 * @param releaseId {int} the release id
 * @param assetId {int} the asset id
 * @throws {Error} kind `"forgejo"` as `call`
 */
export func deleteAsset(c as Client, repo as string, releaseId as int, assetId as int) {
    def path as string init repoPath($repo) + "/releases/" + convert.toString($releaseId) +
        "/assets/" +
        convert.toString($assetId);
    call($c, "DELETE", $path, "");
}

/**
 * The type of a node, `missing` when the pointer does not resolve. Jennifer
 * 0.25.0's `json.typeOf` throws for a missing member instead.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer; "" for the root
 * @return {string} `null`, `bool`, `int`, `float`, `string`, `list`, `map` or `missing`
 */
func kindAt(v as json.Value, ptr as string) {
    if ($ptr == "") {
        return json.typeOf($v);
    }
    if (not json.has($v, $ptr)) {
        return "missing";
    }
    return json.typeOf($v, $ptr);
}

/**
 * Read a node as text, whatever its type.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the text; "" for absent or `null`
 */
func field(v as json.Value, ptr as string) {
    def kind as string init kindAt($v, $ptr);
    if ($kind == "string") {
        return json.asString($v, $ptr);
    } elseif ($kind == "int") {
        return convert.toString(json.asInt($v, $ptr));
    } elseif ($kind == "float") {
        return convert.toString(json.asFloat($v, $ptr));
    } elseif ($kind == "bool") {
        if (json.asBool($v, $ptr)) {
            return "true";
        }
        return "false";
    }
    return "";
}

/**
 * Read a node as an int: a number (truncated) or a numeric string.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {int} the number; 0 for absent, `null` or not numeric
 */
func numberAt(v as json.Value, ptr as string) {
    def kind as string init kindAt($v, $ptr);
    if ($kind == "int") {
        return json.asInt($v, $ptr);
    } elseif ($kind == "float") {
        return convert.toInt(json.asFloat($v, $ptr));
    } elseif ($kind == "string") {
        try {
            return convert.toInt(strings.trim(json.asString($v, $ptr)));
        } catch (e) {
            return 0;
        }
    }
    return 0;
}

/**
 * Read a flag: `true` or `"true"`.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {bool} the flag; false for absent or `null`
 */
func flag(v as json.Value, ptr as string) {
    return field($v, $ptr) == "true";
}

/**
 * The pointers of a list's elements.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the list's pointer
 * @return {list of string} `<ptr>/0`, `<ptr>/1`, ...; empty when it is no list
 */
func items(v as json.Value, ptr as string) {
    def out as list of string init [];
    if (kindAt($v, $ptr) != "list") {
        return $out;
    }
    def n as int init json.length($v, $ptr);
    def i as int init 0;
    while ($i < $n) {
        $out[] = $ptr + "/" + convert.toString($i);
        $i = $i + 1;
    }
    return $out;
}
