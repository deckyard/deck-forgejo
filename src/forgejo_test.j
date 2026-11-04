# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests for forgejo: jennifer test src/forgejo_test.j
 *
 * The checking and parsing helpers are tested directly. The requests go to an
 * `httpd` server on a loopback port that answers with canned Forgejo replies
 * and hands back what it received.
 */
use httpd;
use task;
use testing;

/** A canned reply. */
def struct Reply {
    status as int,
    total as string,
    body as string
};

/** One request as the fake server saw it. */
def struct Seen {
    method as string,
    path as string,
    query as map of string to string,
    auth as string,
    contentType as string,
    body as bytes
};

/** A running fake server. */
def struct Fake {
    srv as httpd.Server,
    url as string,
    t as task of list of Seen
};

/**
 * The query parameters the deck sends. Not `httpd.rawQuery`: 0.25.0 does not
 * have it.
 *
 * @param req {httpd.Request} the request
 * @return {map of string to string} the parameters that are set
 */
func queryOf(req as httpd.Request) {
    def out as map of string to string init {};
    def keys as list of string init ["type", "state", "limit", "page", "name", "ref"];
    $keys = lists.concat($keys, ["sha", "path", "q", "files"]);
    for (def key in $keys) {
        def value as string init httpd.query($req, $key);
        if ($value != "") {
            $out[$key] = $value;
        }
    }
    return $out;
}

/**
 * Answer one request per reply, in order.
 *
 * @param srv {httpd.Server} the listening server
 * @param replies {list of Reply} the replies
 * @return {list of Seen} the requests
 */
func serve(srv as httpd.Server, replies as list of Reply) {
    def seen as list of Seen init [];
    for (def r in $replies) {
        def req as httpd.Request init httpd.accept($srv);
        $seen[] = Seen{
            method: httpd.method($req),
            path: httpd.path($req),
            query: queryOf($req),
            auth: httpd.header($req, "Authorization"),
            contentType: httpd.header($req, "Content-Type"),
            body: httpd.body($req)
        };
        httpd.setHeader($req, "Content-Type", "application/json");
        if ($r.total != "") {
            httpd.setHeader($req, "X-Total-Count", $r.total);
        }
        httpd.respond($req, $r.status, $r.body);
    }
    return $seen;
}

/**
 * Start a fake server that gives these replies.
 *
 * @param replies {list of Reply} the replies
 * @return {Fake} the server
 */
func fake(replies as list of Reply) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of Seen init spawn {
        return serve($srv, $replies);
    };
    return Fake{srv: $srv, url: "http://" + httpd.address($srv), t: $t};
}

/**
 * Stop a fake server.
 *
 * @param f {Fake} the server
 * @return {list of Seen} what it received
 */
func finish(f as Fake) {
    def seen as list of Seen init task.wait($f.t);
    httpd.shutdown($f.srv);
    return $seen;
}

/**
 * A 200 reply.
 *
 * @param body {string} the JSON
 * @return {Reply} the reply
 */
func ok(body as string) {
    return Reply{status: 200, total: "", body: $body};
}

/**
 * A page of a list with its total.
 *
 * @param body {string} the JSON list
 * @param total {int} the X-Total-Count
 * @return {Reply} the reply
 */
func pageOf(body as string, total as int) {
    return Reply{status: 200, total: convert.toString($total), body: $body};
}

/**
 * A JSON list of `n` numbered objects.
 *
 * @param n {int} how many
 * @return {string} the JSON
 */
func entries(n as int) {
    def parts as list of string init [];
    def i as int init 0;
    while ($i < $n) {
        $parts[] = '{"id":' + convert.toString($i) + '}';
        $i = $i + 1;
    }
    return "[" + strings.join($parts, ",") + "]";
}

/**
 * A client for a fake server with a token.
 *
 * @param f {Fake} the server
 * @return {Client} the client
 */
func tokenClient(f as Fake) {
    return withToken(client($f.url), "t0k3n");
}

/**
 * A request body as JSON.
 *
 * @param s {Seen} the request
 * @return {json.Value} the body
 */
func bodyOf(s as Seen) {
    return json.decode(convert.stringFromBytes($s.body, "utf-8"));
}

/**
 * The message of the deck's error.
 *
 * @param e {Error} the error
 * @return {string} its message
 */
func messageOf(e as Error) {
    testing.assertEqual($e.kind, ERROR_KIND);
    return $e.message;
}

/**
 * Fail a test whose call was meant to throw.
 */
func missed() {
    throw Error{kind: "test", message: "the call did not fail"};
}

def const REPO as string init '{"id":7,"owner":{"login":"me"},"name":"app","full_name":"me/app",' +
    '"description":"An app","private":true,"fork":false,"archived":false,"default_branch":"main",' +
    '"html_url":"https://git.example.com/me/app",' +
    '"clone_url":"https://git.example.com/me/app.git",' +
    '"ssh_url":"git@git.example.com:me/app.git","stars_count":3,"open_issues_count":2,' +
    '"updated_at":"2026-11-03T10:00:00Z"}';

def const ISSUE as string init '{"number":12,"title":"Crash on start","body":"It crashes.",' +
    '"state":"open","user":{"login":"ada"},"labels":[{"name":"bug"},{"name":"p1"}],' +
    '"assignees":[{"login":"bob"}],"comments":4,"pull_request":null,' +
    '"created_at":"2026-11-01T09:00:00Z","updated_at":"2026-11-02T09:00:00Z","closed_at":null,' +
    '"html_url":"https://git.example.com/me/app/issues/12"}';

def const PULL as string init '{"number":15,"title":"Fix crash","body":"Fixes #12",' +
    '"state":"open","user":{"login":"bob"},"head":{"ref":"fix-crash","sha":"abc123"},' +
    '"base":{"ref":"main","sha":"def456"},"draft":false,"mergeable":true,"merged":false,' +
    '"merge_commit_sha":null,"html_url":"https://git.example.com/me/app/pulls/15"}';

func testBaseUrl() {
    testing.assertEqual(client("codeberg.org").url, "https://codeberg.org");
    testing.assertEqual(client("git.example.com:3000/").url, "https://git.example.com:3000");
    testing.assertEqual(client("https://example.com/git/api/v1/").url, "https://example.com/git");
    testing.assertEqual(client("http://localhost:3000").url, "http://localhost:3000");
    try {
        client(" ");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "forgejo: the host is empty");
    }
}

func testClientSettings() {
    def c as Client init withRetries(withTimeout(withInsecure(client("codeberg.org")), 5000), 2);
    testing.assertTrue($c.tls.skipVerify);
    testing.assertEqual($c.timeoutMs, 5000);
    testing.assertEqual($c.retries, 2);
    $c = withCaCert($c, convert.bytesFromString("PEM", "utf-8"));
    testing.assertFalse($c.tls.skipVerify);
    testing.assertEqual(withToken($c, "abc").token, "abc");
    try {
        withToken($c, "abc\r\nX-Evil: 1");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "forgejo: a token holds no spaces or control characters");
    }
}

func testNamesAndPathsAreChecked() {
    testing.assertEqual(repoPath("me/app.js"), "/repos/me/app.js");
    for (def bad in ["app", "me/app/x", "../app", "me/..", "me/a b", "me/"]) {
        try {
            repoPath($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a repository is owner/name");
        }
    }
    testing.assertEqual(segments("docs/a b.md", "file path"), "docs/a%20b.md");
    testing.assertEqual(segments("release/1.0", "tag"), "release/1.0");
    testing.assertEqual(segments("v1.0+build", "tag"), "v1.0%2Bbuild");
    for (def bad in ["", "a/../b", "/a", "a//b", "a\nb"]) {
        try {
            segments($bad, "file path");
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a file path");
        }
    }
    for (def bad in ["version", "/a//b", "/a/../b", "/a b", "/a#x"]) {
        try {
            ensurePath($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "an API path");
        }
    }
    ensurePath("/repos/me/app/issues?state=open&type=issues");
    def long as string init strings.repeat("x", 100) + convert.fromCodepoint(10);
    try {
        repoPath($long);
        missed();
    } catch (e) {
        testing.assertFalse(strings.contains(messageOf($e), convert.fromCodepoint(10)));
        testing.assertContains(messageOf($e), "...");
    }
}

func testFailureText() {
    testing.assertEqual(
        failureText(404, "Not Found", '{"message":"The target cannot be found.","url":"x"}'),
        "HTTP 404: The target cannot be found.");
    testing.assertEqual(
        failureText(
            422,
            "Unprocessable Entity",
            '{"message":"invalid","errors":["name is taken","bad"]}'),
        "HTTP 422: invalid (name is taken; bad)");
    testing.assertEqual(failureText(502, "Bad Gateway", "<html>"), "HTTP 502: Bad Gateway");
    # The server's text stays one bounded line.
    def said as string init failureText(
        500,
        "",
        '{"message":"line one\nforged: line two ' + strings.repeat("x", 500) + '"}');
    testing.assertFalse(strings.contains($said, convert.fromCodepoint(10)));
    testing.assertContains($said, "line one?forged");
    testing.assertTrue(len($said) < 250);
}

func testIdleTimeout() {
    # http's raw and bytes requests take 0 as no timeout at all.
    testing.assertEqual(idleMs(client("x")), 30000);
    testing.assertEqual(idleMs(withTimeout(client("x"), 500)), 500);
}

func testTagPath() {
    testing.assertEqual(tagPath("me/app", "1.2.0"), "/repos/me/app/releases/tags/1.2.0");
    testing.assertEqual(
        tagPath("me/app", "release/1.0"),
        "/repos/me/app/releases/tags/release%2F1.0");
    try {
        tagPath("me/app", "a/../b");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a tag has no empty");
    }
}

func testCallSendsTheToken() {
    def f as Fake init fake([
        ok('{"version":"9.0.0+gitea-1.22.0"}'),
        ok('{"id":1,"login":"me","is_admin":true}')
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(version($c), "9.0.0+gitea-1.22.0");
    def u as User init currentUser($c);
    def seen as list of Seen init finish($f);
    testing.assertEqual($u.login, "me");
    testing.assertTrue($u.isAdmin);
    testing.assertEqual($seen[0].method, "GET");
    testing.assertEqual($seen[0].path, "/api/v1/version");
    testing.assertEqual($seen[0].auth, "token t0k3n");
    testing.assertEqual($seen[1].path, "/api/v1/user");
}

func testRefusalsNameTheRequest() {
    def f as Fake init fake([
        Reply{status: 404, total: "", body: '{"message":"repo does not exist"}'}
    ]);
    try {
        repository(tokenClient($f), "me/missing");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "forgejo: GET /repos/me/missing: HTTP 404: repo does not exist");
    }
    finish($f);
    try {
        call(client("x"), "TRACE", "/version", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "unsupported method");
    }
}

func testGetAllFollowsTheTotal() {
    def f as Fake init fake([pageOf(entries(50), 52), pageOf(entries(2), 52)]);
    def got as list of json.Value init getAll(tokenClient($f), "/repos/me/app/issues?state=open");
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($got), 52);
    testing.assertEqual(len($seen), 2);
    testing.assertEqual($seen[0].query["state"], "open");
    testing.assertEqual($seen[0].query["limit"], "50");
    testing.assertEqual($seen[0].query["page"], "1");
    testing.assertEqual($seen[1].query["page"], "2");
}

func testGetAllWithASmallerServerPage() {
    # An admin lowered the page size: short pages, yet more to come.
    def f as Fake init fake([pageOf(entries(3), 5), pageOf(entries(2), 5)]);
    def got as list of json.Value init getAll(tokenClient($f), "/user/repos");
    finish($f);
    testing.assertEqual(len($got), 5);
}

func testGetAllWithoutATotal() {
    def f as Fake init fake([ok(entries(50)), ok(entries(10))]);
    def got as list of json.Value init getAll(tokenClient($f), "/user/repos");
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($got), 60);
    testing.assertEqual($seen[1].query["page"], "2");
    def g as Fake init fake([ok('{"not":"a list"}')]);
    try {
        getAll(tokenClient($g), "/user/repos");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "forgejo: GET /user/repos: the reply is not a list");
    }
    finish($g);
}

func testRepositories() {
    def f as Fake init fake([
        ok(REPO),
        pageOf("[" + REPO + "]", 1),
        ok(REPO),
        ok(REPO),
        ok(""),
        pageOf("[" + REPO + "," + REPO + "]", 2)
    ]);
    def c as Client init tokenClient($f);
    def r as Repository init repository($c, "me/app");
    testing.assertEqual($r.fullName, "me/app");
    testing.assertEqual($r.owner, "me");
    testing.assertTrue($r.isPrivate);
    testing.assertEqual($r.defaultBranch, "main");
    testing.assertEqual($r.sshUrl, "git@git.example.com:me/app.git");
    testing.assertEqual($r.openIssues, 2);
    testing.assertEqual(len(repositories($c, "me")), 1);
    createRepository($c, "", "app", "An app", true);
    createRepository($c, "acme", "app", "", false);
    deleteRepository($c, "me/app");
    testing.assertEqual(len(myRepositories($c)), 2);
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[1].path, "/api/v1/users/me/repos");
    testing.assertEqual($seen[2].method, "POST");
    testing.assertEqual($seen[2].path, "/api/v1/user/repos");
    testing.assertEqual($seen[2].contentType, "application/json");
    testing.assertEqual(
        json.encode(bodyOf($seen[2])),
        '{"description":"An app","name":"app","private":true}');
    testing.assertEqual($seen[3].path, "/api/v1/orgs/acme/repos");
    testing.assertEqual(json.encode(bodyOf($seen[3])), '{"name":"app","private":false}');
    testing.assertEqual($seen[4].method, "DELETE");
    testing.assertEqual($seen[4].path, "/api/v1/repos/me/app");
    testing.assertEqual($seen[5].path, "/api/v1/user/repos");
}

func testIssues() {
    def f as Fake init fake([
        pageOf("[" + ISSUE + "]", 1),
        ok(ISSUE),
        ok(ISSUE),
        ok(ISSUE),
        ok(ISSUE),
        ok('{"id":99,"user":{"login":"me"},"body":"On it","created_at":"t","html_url":"u"}'),
        pageOf('[{"id":1,"user":{"login":"ada"},"body":"first"}]', 1)
    ]);
    def c as Client init tokenClient($f);
    def got as list of Issue init issues($c, "me/app", "open");
    testing.assertEqual(len($got), 1);
    testing.assertEqual($got[0].number, 12);
    testing.assertEqual($got[0].author, "ada");
    testing.assertEqual($got[0].labels, ["bug", "p1"]);
    testing.assertEqual($got[0].assignees, ["bob"]);
    testing.assertFalse($got[0].isPull);
    testing.assertEqual($got[0].closed, "");
    testing.assertEqual(issue($c, "me/app", 12).title, "Crash on start");
    createIssue($c, "me/app", "Crash on start", "");
    closeIssue($c, "me/app", 12);
    reopenIssue($c, "me/app", 12);
    def made as Comment init comment($c, "me/app", 12, "On it");
    testing.assertEqual($made.id, 99);
    testing.assertEqual(comments($c, "me/app", 12)[0].body, "first");
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v1/repos/me/app/issues");
    testing.assertEqual($seen[0].query["type"], "issues");
    testing.assertEqual($seen[0].query["state"], "open");
    testing.assertEqual($seen[1].path, "/api/v1/repos/me/app/issues/12");
    testing.assertEqual(json.encode(bodyOf($seen[2])), '{"title":"Crash on start"}');
    testing.assertEqual($seen[3].method, "PATCH");
    testing.assertEqual(json.encode(bodyOf($seen[3])), '{"state":"closed"}');
    testing.assertEqual(json.encode(bodyOf($seen[4])), '{"state":"open"}');
    testing.assertEqual($seen[5].path, "/api/v1/repos/me/app/issues/12/comments");
    testing.assertEqual(json.encode(bodyOf($seen[5])), '{"body":"On it"}');
    try {
        issues($c, "me/app", "opened");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a state is open, closed or all");
    }
    try {
        createIssue($c, "me/app", " ", "x");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "forgejo: an issue needs a title");
    }
}

func testPullRequests() {
    def f as Fake init fake([pageOf("[" + PULL + "]", 1), ok(PULL), ok(PULL), ok("")]);
    def c as Client init tokenClient($f);
    def got as list of PullRequest init pullRequests($c, "me/app", "all");
    testing.assertEqual($got[0].head, "fix-crash");
    testing.assertEqual($got[0].base, "main");
    testing.assertEqual($got[0].headSha, "abc123");
    testing.assertTrue($got[0].mergeable);
    testing.assertEqual($got[0].mergeSha, "");
    testing.assertEqual(pullRequest($c, "me/app", 15).number, 15);
    createPullRequest($c, "me/app", "fix-crash", "main", "Fix crash", "Fixes #12");
    mergePullRequest($c, "me/app", 15, "squash", true);
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].query["state"], "all");
    testing.assertEqual(
        json.encode(bodyOf($seen[2])),
        '{"base":"main","body":"Fixes #12","head":"fix-crash","title":"Fix crash"}');
    testing.assertEqual($seen[3].path, "/api/v1/repos/me/app/pulls/15/merge");
    testing.assertEqual(
        json.encode(bodyOf($seen[3])),
        '{"Do":"squash","delete_branch_after_merge":true}');
    try {
        mergePullRequest($c, "me/app", 15, "octopus", false);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a merge style is one of merge, rebase");
    }
}

func testReleasesAndAssets() {
    def f as Fake init fake([]);
    def base as string init $f.url;
    finish($f);
    def rel as string init '{"id":5,"tag_name":"1.2.0","name":"1.2.0","body":"Notes",' +
        '"draft":false,' +
        '"prerelease":true,"created_at":"c","published_at":"p","html_url":"h","assets":[' +
        '{"id":9,"name":"app.tar.gz","size":1234,"download_count":7,' +
        '"browser_download_url":"' + $base + '/me/app/releases/download/1.2.0/app.tar.gz"}]}';
    def g as Fake init fake([
        pageOf("[" + $rel + "]", 1),
        ok($rel),
        ok($rel),
        ok('{"id":10,"name":"app.zip","size":3,"download_count":0,"browser_download_url":"x"}'),
        ok(""),
        Reply{status: 200, total: "", body: "BINARY"}
    ]);
    def c as Client init withToken(client($g.url), "t0k3n");
    def got as list of Release init releases($c, "me/app");
    testing.assertEqual($got[0].tag, "1.2.0");
    testing.assertTrue($got[0].isPrerelease);
    testing.assertEqual($got[0].assets[0].name, "app.tar.gz");
    testing.assertEqual($got[0].assets[0].size, 1234);
    testing.assertEqual($got[0].assets[0].downloads, 7);
    testing.assertEqual(release($c, "me/app", "1.2.0").id, 5);
    createRelease($c, "me/app", "1.2.0", "", "", "Notes", true);
    def a as Asset init uploadAsset(
        $c,
        "me/app",
        5,
        "app.zip",
        convert.bytesFromString("zip", "utf-8"));
    testing.assertEqual($a.id, 10);
    deleteRelease($c, "me/app", 5);
    # The asset URL points at the fake server's old port, not this client's.
    try {
        downloadAsset($c, $got[0].assets[0], 0);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "is not on " + $c.url);
    }
    def local as Asset init $got[0].assets[0];
    $local.downloadUrl = $c.url + "/me/app/releases/download/1.2.0/app.tar.gz";
    testing.assertEqual(convert.stringFromBytes(downloadAsset($c, $local, 0), "utf-8"), "BINARY");
    def seen as list of Seen init finish($g);
    testing.assertEqual($seen[1].path, "/api/v1/repos/me/app/releases/tags/1.2.0");
    testing.assertEqual(
        json.encode(bodyOf($seen[2])),
        '{"body":"Notes","tag_name":"1.2.0","draft":false,"prerelease":true}');
    testing.assertEqual($seen[3].path, "/api/v1/repos/me/app/releases/5/assets");
    testing.assertEqual($seen[3].query["name"], "app.zip");
    def parts as list of multipart.Part init multipart.parse($seen[3].contentType, $seen[3].body);
    testing.assertEqual($parts[0].name, "attachment");
    testing.assertEqual($parts[0].filename, "app.zip");
    testing.assertEqual($seen[4].method, "DELETE");
    testing.assertEqual($seen[5].path, "/me/app/releases/download/1.2.0/app.tar.gz");
    testing.assertEqual($seen[5].auth, "token t0k3n");
}

func testBranchesAndTags() {
    def f as Fake init fake([
        pageOf('[{"name":"main","commit":{"id":"aaa"},"protected":true}]', 1),
        pageOf('[{"name":"1.0.0","message":"","commit":{"sha":"bbb"}}]', 1)
    ]);
    def c as Client init tokenClient($f);
    def b as list of Branch init branches($c, "me/app");
    def t as list of Tag init tags($c, "me/app");
    finish($f);
    testing.assertEqual($b[0].sha, "aaa");
    testing.assertTrue($b[0].isProtected);
    testing.assertEqual($t[0].name, "1.0.0");
    testing.assertEqual($t[0].sha, "bbb");
}

func testFiles() {
    def f as Fake init fake([
        ok("hello"),
        Reply{status: 404, total: "", body: '{"message":"not found"}'},
        ok('{"content":{"sha":"blob1"},"commit":{"sha":"c1"}}'),
        ok('{"sha":"blob1","content":"aGVsbG8="}'),
        ok('{"content":{"sha":"blob2"},"commit":{"sha":"c2"}}'),
        Reply{status: 502, total: "", body: '{"message":"upstream: HTTP 404"}'}
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(
        convert.stringFromBytes(readFile($c, "me/app", "docs/a b.md", "dev"), "utf-8"),
        "hello");
    def data as bytes init convert.bytesFromString("hello", "utf-8");
    testing.assertEqual(writeFile($c, "me/app", "data/v.txt", $data, "add v", ""), "c1");
    testing.assertEqual(writeFile($c, "me/app", "data/v.txt", $data, "bump v", "dev"), "c2");
    # Only a 404 for the file itself means create; this one is no 404.
    try {
        writeFile($c, "me/app", "data/v.txt", $data, "bump v", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 502");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v1/repos/me/app/media/docs/a b.md");
    testing.assertEqual($seen[0].query["ref"], "dev");
    testing.assertEqual($seen[1].method, "GET");
    testing.assertEqual($seen[2].method, "POST");
    testing.assertEqual($seen[2].path, "/api/v1/repos/me/app/contents/data/v.txt");
    testing.assertEqual(json.encode(bodyOf($seen[2])), '{"content":"aGVsbG8=","message":"add v"}');
    testing.assertEqual($seen[3].query["ref"], "dev");
    testing.assertEqual($seen[4].method, "PUT");
    testing.assertEqual(
        json.encode(bodyOf($seen[4])),
        '{"branch":"dev","content":"aGVsbG8=","message":"bump v","sha":"blob1"}');
    try {
        writeFile($c, "me/app", "x", $data, " ", "");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "forgejo: a commit needs a message");
    }
}

func testHeadOfAMergedPullRequest() {
    def d as json.Value init json.decode(
        '{"head":{"label":"bp-fix","ref":"refs/pull/7/head","sha":"x"},"base":{"ref":"main"}}');
    testing.assertEqual(pullFrom($d).head, "bp-fix");
    testing.assertEqual(pullFrom(json.decode(PULL)).head, "fix-crash");
}

func testReaders() {
    def d as json.Value init json.decode('{"a":"12","b":3.9,"c":true,"e":null,"l":[1,2]}');
    testing.assertEqual(numberAt($d, "/a"), 12);
    testing.assertEqual(numberAt($d, "/b"), 3);
    testing.assertEqual(numberAt($d, "/missing"), 0);
    testing.assertEqual(field($d, "/e"), "");
    testing.assertTrue(flag($d, "/c"));
    testing.assertFalse(flag($d, "/missing"));
    testing.assertEqual(items($d, "/l"), ["/l/0", "/l/1"]);
    testing.assertEqual(countOf("52"), 52);
    testing.assertEqual(countOf("x"), 0);
    testing.assertEqual(objectOf({"a": "1", "b": ""}, {"c": true}), '{"a":"1","c":true}');
}

func testCommitStatuses() {
    def status as string init '{"context":"ci/build","status":"success","description":"ok",' +
        '"target_url":"https://ci/1","creator":{"login":"bot"},"created_at":"t"}';
    def f as Fake init fake([
        ok($status),
        pageOf("[" + $status + "]", 1),
        ok('{"state":"failure","statuses":[' + $status + ']}')
    ]);
    def c as Client init tokenClient($f);
    def made as CommitStatus init setCommitStatus(
        $c,
        "me/app",
        "abc123",
        "success",
        "ci/build",
        "ok",
        "https://ci/1");
    def all as list of CommitStatus init commitStatuses($c, "me/app", "main");
    def combined as CombinedStatus init combinedStatus($c, "me/app", "main");
    def seen as list of Seen init finish($f);
    testing.assertEqual($made.state, "success");
    testing.assertEqual($made.creator, "bot");
    testing.assertEqual($all[0].targetUrl, "https://ci/1");
    testing.assertEqual($combined.state, "failure");
    testing.assertEqual(len($combined.statuses), 1);
    testing.assertEqual($seen[0].path, "/api/v1/repos/me/app/statuses/abc123");
    testing.assertEqual(
        json.encode(bodyOf($seen[0])),
        '{"context":"ci/build","description":"ok","state":"success","target_url":"https://ci/1"}');
    testing.assertEqual($seen[1].path, "/api/v1/repos/me/app/commits/main/statuses");
    testing.assertEqual($seen[2].path, "/api/v1/repos/me/app/commits/main/status");
    try {
        setCommitStatus($c, "me/app", "abc", "passed", "ci", "", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a commit status is one of pending");
    }
}

func testCommits() {
    def one as string init '{"sha":"abc","html_url":"h","commit":{"message":"Fix it",' +
        '"author":{"name":"Ada","email":"ada@example.com","date":"2026-11-01T10:00:00Z"}}}';
    def f as Fake init fake([pageOf("[" + $one + "]", 1), ok($one)]);
    def c as Client init tokenClient($f);
    def all as list of Commit init commits($c, "me/app", "dev", "src");
    def single as Commit init commit($c, "me/app", "abc");
    def seen as list of Seen init finish($f);
    testing.assertEqual($all[0].message, "Fix it");
    testing.assertEqual($all[0].authorEmail, "ada@example.com");
    testing.assertEqual($single.date, "2026-11-01T10:00:00Z");
    testing.assertEqual($seen[0].query["sha"], "dev");
    testing.assertEqual($seen[0].query["path"], "src");
    testing.assertEqual($seen[0].query["files"], "false");
    testing.assertEqual($seen[1].path, "/api/v1/repos/me/app/git/commits/abc");
}

func testRefsAreEncodedOnce() {
    def f as Fake init fake([ok('{"sha":"x"}'), ok('{"id":1}')]);
    def c as Client init tokenClient($f);
    commit($c, "me/app", "feature/a b");
    dispatchWorkflow($c, "me/app", "my flow.yml", "main", {});
    def seen as list of Seen init finish($f);
    # httpd hands back the decoded path: one encoding, one decoding.
    testing.assertEqual($seen[0].path, "/api/v1/repos/me/app/git/commits/feature/a b");
    testing.assertEqual(
        $seen[1].path,
        "/api/v1/repos/me/app/actions/workflows/my flow.yml/dispatches");
}

func testActions() {
    def f as Fake init fake([
        ok('{"id":77,"run_number":5,"jobs":["build"]}'),
        ok(""),
        ok(""),
        pageOf('[{"name":"REGION","data":"eu"}]', 1),
        Reply{status: 404, total: "", body: '{"message":"not found"}'},
        ok(""),
        ok(""),
        ok("")
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(
        dispatchWorkflow($c, "me/app", "release.yml", "main", {"level": "minor"}),
        77);
    setSecret($c, "me/app", "DEPLOY_KEY", "s3cret");
    deleteSecret($c, "me/app", "DEPLOY_KEY");
    testing.assertEqual(variables($c, "me/app")["REGION"], "eu");
    setVariable($c, "me/app", "REGION", "us");
    setVariable($c, "me/app", "REGION", "ap");
    deleteVariable($c, "me/app", "REGION");
    def seen as list of Seen init finish($f);
    testing.assertEqual(
        $seen[0].path,
        "/api/v1/repos/me/app/actions/workflows/release.yml/dispatches");
    testing.assertEqual(
        json.encode(bodyOf($seen[0])),
        '{"return_run_info":true,"ref":"main","inputs":{"level":"minor"}}');
    testing.assertEqual($seen[1].method, "PUT");
    testing.assertEqual(json.encode(bodyOf($seen[1])), '{"data":"s3cret"}');
    testing.assertEqual($seen[2].method, "DELETE");
    # Update answers 404 for a new variable: create it.
    testing.assertEqual($seen[4].method, "PUT");
    testing.assertEqual($seen[5].method, "POST");
    testing.assertEqual(json.encode(bodyOf($seen[5])), '{"value":"us"}');
    testing.assertEqual($seen[6].method, "PUT");
    testing.assertEqual($seen[7].method, "DELETE");
    for (def bad in ["1ABC", "FORGEJO_TOKEN", "a-b"]) {
        try {
            setSecret($c, "me/app", $bad, "x");
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a secret or variable name");
        }
    }
}

func testEditing() {
    def rel as string init '{"id":5,"tag_name":"1.2.0","name":"Final","assets":[]}';
    def f as Fake init fake([
        ok(ISSUE),
        ok(ISSUE),
        ok(ISSUE),
        ok(PULL),
        ok($rel),
        ok('{"id":9,"body":"better","user":{"login":"me"}}'),
        ok(""),
        ok(REPO),
        ok(REPO),
        ok(REPO)
    ]);
    def c as Client init tokenClient($f);
    editIssue($c, "me/app", 12, "Crash on start", "");
    setAssignees($c, "me/app", 12, ["bob", "ada"]);
    setMilestone($c, "me/app", 12, 3);
    editPullRequest($c, "me/app", 15, "", "New text");
    testing.assertEqual(editRelease($c, "me/app", 5, "Final", "").name, "Final");
    testing.assertEqual(editComment($c, "me/app", 9, "better").body, "better");
    deleteComment($c, "me/app", 9);
    editRepository($c, "me/app", "An app", "https://app.example.com");
    setArchived($c, "me/app", true);
    setDefaultBranch($c, "me/app", "trunk");
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "PATCH");
    testing.assertEqual(json.encode(bodyOf($seen[0])), '{"title":"Crash on start"}');
    testing.assertEqual(json.encode(bodyOf($seen[1])), '{"assignees":["bob","ada"]}');
    testing.assertEqual(json.encode(bodyOf($seen[2])), '{"milestone":3}');
    testing.assertEqual($seen[3].path, "/api/v1/repos/me/app/pulls/15");
    testing.assertEqual(json.encode(bodyOf($seen[3])), '{"body":"New text"}');
    testing.assertEqual($seen[4].path, "/api/v1/repos/me/app/releases/5");
    testing.assertEqual($seen[5].path, "/api/v1/repos/me/app/issues/comments/9");
    testing.assertEqual($seen[6].method, "DELETE");
    testing.assertEqual(
        json.encode(bodyOf($seen[7])),
        '{"description":"An app","website":"https://app.example.com"}');
    testing.assertEqual(json.encode(bodyOf($seen[8])), '{"archived":true}');
    testing.assertEqual(json.encode(bodyOf($seen[9])), '{"default_branch":"trunk"}');
}

func testLabelsAndMilestones() {
    def label as string init '{"id":4,"name":"bug","color":"ee0701","description":"",' +
        '"exclusive":false}';
    def milestone as string init '{"id":3,"title":"1.0","state":"open","due_on":null,' +
        '"open_issues":2,"closed_issues":5}';
    def f as Fake init fake([
        pageOf("[" + $label + "]", 1),
        ok($label),
        ok(""),
        ok("[" + $label + "]"),
        ok("[" + $label + "]"),
        ok(""),
        pageOf("[" + $milestone + "]", 1),
        ok($milestone),
        ok($milestone),
        ok("")
    ]);
    def c as Client init tokenClient($f);
    def first as Label init labels($c, "me/app")[0];
    testing.assertEqual($first.name, "bug");
    testing.assertEqual($first.color, "#ee0701");
    testing.assertEqual(createLabel($c, "me/app", "bug", "#ee0701", "").id, 4);
    deleteLabel($c, "me/app", 4);
    testing.assertEqual(len(setIssueLabels($c, "me/app", 12, ["bug"])), 1);
    addIssueLabels($c, "me/app", 12, ["bug"]);
    removeIssueLabel($c, "me/app", 12, "scope/ui");
    def ms as list of Milestone init milestones($c, "me/app", "open");
    createMilestone($c, "me/app", "1.0", "", "2026-12-31T00:00:00Z");
    setMilestoneClosed($c, "me/app", 3, true);
    deleteMilestone($c, "me/app", 3);
    def seen as list of Seen init finish($f);
    testing.assertEqual($ms[0].closedIssues, 5);
    testing.assertEqual($ms[0].dueOn, "");
    testing.assertEqual(json.encode(bodyOf($seen[1])), '{"color":"#ee0701","name":"bug"}');
    testing.assertEqual($seen[3].method, "PUT");
    testing.assertEqual(json.encode(bodyOf($seen[3])), '{"labels":["bug"]}');
    testing.assertEqual($seen[4].method, "POST");
    testing.assertEqual($seen[5].path, "/api/v1/repos/me/app/issues/12/labels/scope/ui");
    testing.assertEqual($seen[6].query["state"], "open");
    testing.assertEqual(
        json.encode(bodyOf($seen[7])),
        '{"due_on":"2026-12-31T00:00:00Z","title":"1.0"}');
    testing.assertEqual(json.encode(bodyOf($seen[8])), '{"state":"closed"}');
    try {
        createLabel($c, "me/app", "bug", "red", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a label colour is #rrggbb");
    }
}

func testRefsAndFiles() {
    def f as Fake init fake([
        ok('{"name":"feature","commit":{"id":"abc"},"protected":false}'),
        ok(""),
        ok('{"name":"1.2.0","message":"Release","commit":{"sha":"abc"}}'),
        ok(""),
        ok('{"sha":"blob1","type":"file"}'),
        ok('{"commit":{"sha":"c9"}}'),
        ok('[{"name":"README.md","path":"README.md","type":"file","size":12,"sha":"b1"},' +
            '{"name":"src","path":"src","type":"dir","size":0,"sha":"t1"}]'),
        ok('{"name":"README.md","type":"file"}')
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(createBranch($c, "me/app", "feature", "main").sha, "abc");
    deleteBranch($c, "me/app", "feature");
    testing.assertEqual(createTag($c, "me/app", "1.2.0", "main", "Release").message, "Release");
    deleteTag($c, "me/app", "1.2.0");
    testing.assertEqual(deleteFile($c, "me/app", "old.txt", "remove old", "dev"), "c9");
    def entries as list of Entry init listDirectory($c, "me/app", "", "main");
    try {
        listDirectory($c, "me/app", "README.md", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "is not a directory");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual(
        json.encode(bodyOf($seen[0])),
        '{"new_branch_name":"feature","old_ref_name":"main"}');
    testing.assertEqual($seen[1].path, "/api/v1/repos/me/app/branches/feature");
    testing.assertEqual(
        json.encode(bodyOf($seen[2])),
        '{"message":"Release","tag_name":"1.2.0","target":"main"}');
    testing.assertEqual($seen[3].path, "/api/v1/repos/me/app/tags/1.2.0");
    testing.assertEqual($seen[4].query["ref"], "dev");
    testing.assertEqual($seen[5].method, "DELETE");
    testing.assertEqual(
        json.encode(bodyOf($seen[5])),
        '{"branch":"dev","message":"remove old","sha":"blob1"}');
    testing.assertEqual($entries[1].type, "dir");
    testing.assertEqual($entries[0].size, 12);
    testing.assertEqual($seen[6].path, "/api/v1/repos/me/app/contents");
}

func testReviews() {
    def review as string init '{"id":8,"user":{"login":"bob"},"state":"APPROVED","body":"",' +
        '"commit_id":"abc","submitted_at":"t"}';
    def f as Fake init fake([
        ok($review),
        pageOf("[" + $review + "]", 1),
        ok("[]"),
        pageOf('[{"filename":"src/a.j","status":"changed","additions":3,"deletions":1}]', 1)
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(reviewPullRequest($c, "me/app", 15, "APPROVED", "").state, "APPROVED");
    testing.assertEqual(reviews($c, "me/app", 15)[0].author, "bob");
    requestReviewers($c, "me/app", 15, ["ada"]);
    def files as list of ChangedFile init pullRequestFiles($c, "me/app", 15);
    def seen as list of Seen init finish($f);
    testing.assertEqual($files[0].additions, 3);
    testing.assertEqual($seen[0].path, "/api/v1/repos/me/app/pulls/15/reviews");
    testing.assertEqual(json.encode(bodyOf($seen[0])), '{"event":"APPROVED"}');
    testing.assertEqual(json.encode(bodyOf($seen[2])), '{"reviewers":["ada"]}');
    testing.assertEqual($seen[3].path, "/api/v1/repos/me/app/pulls/15/files");
    try {
        reviewPullRequest($c, "me/app", 15, "REQUEST_CHANGES", " ");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "review needs a text");
    }
}

func testRepositoryAdmin() {
    def hook as string init '{"id":2,"type":"forgejo","config":{"url":"https://ci/hook",' +
        '"content_type":"json"},"events":["push"],"active":true}';
    def rel as string init '{"id":5,"tag_name":"1.2.0","assets":[]}';
    def f as Fake init fake([
        pageOf("[" + $hook + "]", 1),
        ok($hook),
        ok(""),
        pageOf('[{"id":3,"login":"ada"}]', 1),
        ok(""),
        ok(""),
        Reply{status: 202, total: "", body: REPO},
        Reply{status: 200, total: "2", body: '{"ok":true,"data":[' + REPO + "," + REPO + ']}'},
        ok($rel),
        ok("")
    ]);
    def c as Client init tokenClient($f);
    testing.assertEqual(hooks($c, "me/app")[0].url, "https://ci/hook");
    testing.assertEqual(createHook($c, "me/app", "https://ci/hook", "s", ["push"]).id, 2);
    deleteHook($c, "me/app", 2);
    testing.assertEqual(collaborators($c, "me/app")[0].login, "ada");
    addCollaborator($c, "me/app", "ada", "write");
    removeCollaborator($c, "me/app", "ada");
    testing.assertEqual(forkRepository($c, "forgejo/forgejo", "", "my-forgejo").name, "app");
    testing.assertEqual(len(searchRepositories($c, "jennifer deck")), 2);
    testing.assertEqual(latestRelease($c, "me/app").tag, "1.2.0");
    deleteAsset($c, "me/app", 5, 9);
    def seen as list of Seen init finish($f);
    testing.assertEqual(
        json.encode(bodyOf($seen[1])),
        '{"type":"forgejo","active":true,"config":{"content_type":"json","secret":"s",' +
            '"url":"https://ci/hook"},"events":["push"]}');
    testing.assertEqual($seen[4].path, "/api/v1/repos/me/app/collaborators/ada");
    testing.assertEqual(json.encode(bodyOf($seen[4])), '{"permission":"write"}');
    testing.assertEqual($seen[6].path, "/api/v1/repos/forgejo/forgejo/forks");
    testing.assertEqual(json.encode(bodyOf($seen[6])), '{"name":"my-forgejo"}');
    testing.assertEqual($seen[7].query["q"], "jennifer deck");
    testing.assertEqual($seen[8].path, "/api/v1/repos/me/app/releases/latest");
    testing.assertEqual($seen[9].path, "/api/v1/repos/me/app/releases/5/assets/9");
    try {
        createHook($c, "me/app", "ftp://x", "", ["push"]);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a webhook URL is http");
    }
    try {
        addCollaborator($c, "me/app", "ada", "owner");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a permission is read, write or admin");
    }
}
