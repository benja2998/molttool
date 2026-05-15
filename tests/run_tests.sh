#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/moltbook.sh"

TEST_TMP=""
TEST_COUNT=0
FAIL_COUNT=0
LAST_STATUS=0
LAST_OUT=""
LAST_ERR=""

cleanup() {
    if [[ -n "$TEST_TMP" ]]; then
	rm -rf "$TEST_TMP"
    fi
}
trap cleanup EXIT

fail() {
    local message="$1"
    printf 'not ok %d - %s\n' "$TEST_COUNT" "$message"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    local message="$1"
    printf 'ok %d - %s\n' "$TEST_COUNT" "$message"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    if [[ "$actual" == "$expected" ]]; then
	pass "$message"
    else
	fail "$message"
	printf '  expected: %s\n' "$expected"
	printf '  actual:   %s\n' "$actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
	pass "$message"
    else
	fail "$message"
	printf '  expected to contain: %s\n' "$needle"
	printf '  actual: %s\n' "$haystack"
    fi
}

assert_json_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    if jq -e --argjson expected "$expected" --argjson actual "$actual" -n '$actual == $expected' >/dev/null; then
	pass "$message"
    else
	fail "$message"
	printf '  expected JSON: %s\n' "$expected"
	printf '  actual JSON:   %s\n' "$actual"
    fi
}

write_fake_curl() {
    mkdir -p "$TEST_TMP/bin"
    cat >"$TEST_TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""
data=""
auth=""
content_type=""

while (($#)); do
    case "$1" in
	-X)
	    method="$2"
	    shift 2
	    ;;
	-H)
	    case "$2" in
		Authorization:*) auth="$2" ;;
		Content-Type:*) content_type="$2" ;;
	    esac
	    shift 2
	    ;;
	-d)
	    data="$2"
	    shift 2
	    ;;
	-sS)
	    shift
	    ;;
	*)
	    url="$1"
	    shift
	    ;;
    esac
done

jq -cn \
    --arg method "$method" \
    --arg url "$url" \
    --arg data "$data" \
    --arg auth "$auth" \
    --arg content_type "$content_type" \
    '{method:$method,url:$url,data:$data,auth:$auth,content_type:$content_type}' >>"$FAKE_CURL_LOG"

if [[ -n "${FAKE_CURL_CHALLENGE_SUFFIX:-}" && "$url" == *"$FAKE_CURL_CHALLENGE_SUFFIX" ]]; then
    if [[ -n "${FAKE_CURL_CHALLENGE_RESPONSE:-}" ]]; then
	printf '%s\n' "$FAKE_CURL_CHALLENGE_RESPONSE"
    else
	printf '%s\n' '{"verification":{"verification_code":"123"}}'
    fi
elif [[ "$url" == */verify && -n "${FAKE_CURL_VERIFY_RESPONSE:-}" ]]; then
    printf '%s\n' "$FAKE_CURL_VERIFY_RESPONSE"
elif [[ -n "${FAKE_CURL_RESPONSE:-}" ]]; then
    printf '%s\n' "$FAKE_CURL_RESPONSE"
else
    printf '%s\n' '{"ok":true}'
fi
EOF
    chmod +x "$TEST_TMP/bin/curl"
}

setup_test() {
    TEST_TMP="$(mktemp -d)"
    export FAKE_CURL_LOG="$TEST_TMP/curl.log"
    export FAKE_CURL_RESPONSE='{"ok":true}'
    unset FAKE_CURL_CHALLENGE_SUFFIX FAKE_CURL_CHALLENGE_RESPONSE FAKE_CURL_VERIFY_RESPONSE || true
    : >"$FAKE_CURL_LOG"
    write_fake_curl
}

run_cli() {
    local stdin="$1"
    shift

    local out="$TEST_TMP/stdout"
    local err="$TEST_TMP/stderr"
    set +e
    printf '%s' "$stdin" | PATH="$TEST_TMP/bin:$PATH" HOME="$TEST_TMP/home" MOLTBOOK_API_KEY="${MOLTBOOK_API_KEY:-test-key}" bash "$SCRIPT" "$@" >"$out" 2>"$err"
    LAST_STATUS=$?
    set -e
    LAST_OUT="$(cat "$out")"
    LAST_ERR="$(cat "$err")"
}

run_cli_without_env_key() {
    local stdin="$1"
    shift

    local out="$TEST_TMP/stdout"
    local err="$TEST_TMP/stderr"
    set +e
    printf '%s' "$stdin" | env -u MOLTBOOK_API_KEY PATH="$TEST_TMP/bin:$PATH" HOME="$TEST_TMP/home" bash "$SCRIPT" "$@" >"$out" 2>"$err"
    LAST_STATUS=$?
    set -e
    LAST_OUT="$(cat "$out")"
    LAST_ERR="$(cat "$err")"
}

request_count() {
    wc -l <"$FAKE_CURL_LOG" | tr -d ' '
}

request_json() {
    local index="${1:-1}"
    sed -n "${index}p" "$FAKE_CURL_LOG"
}

request_field() {
    local index="$1"
    local field="$2"
    request_json "$index" | jq -r ".$field"
}

last_request_field() {
    local field="$1"
    jq -r ".$field" "$FAKE_CURL_LOG" | tail -n 1
}

last_request_data() {
    jq -r 'select(.data != "") | .data | fromjson | tojson' "$FAKE_CURL_LOG" | tail -n 1
}

assert_last_request() {
    local expected_method="$1"
    local expected_url="$2"
    local message="$3"

    assert_eq "$expected_method" "$(last_request_field method)" "$message method"
    assert_eq "https://www.moltbook.com/api/v1${expected_url}" "$(last_request_field url)" "$message URL"
    assert_eq "Authorization: Bearer test-key" "$(last_request_field auth)" "$message authorization header"
}

test_help_and_auth() {
    setup_test
    run_cli "" --help
    assert_eq 0 "$LAST_STATUS" "help exits successfully"
    assert_contains "$LAST_OUT" "moltbook.sh dm-send <conversation_id>" "help includes DM commands"
    assert_eq 0 "$(request_count)" "help does not call curl"

    setup_test
    run_cli_without_env_key "" home
    assert_eq 1 "$LAST_STATUS" "missing API key exits with failure"
    assert_contains "$LAST_ERR" "Please set MOLTBOOK_API_KEY" "missing API key prints guidance"
    assert_eq 0 "$(request_count)" "missing API key does not call curl"

    setup_test
    mkdir -p "$TEST_TMP/home/.config/moltbook"
    printf '{"api_key":"file-key"}\n' >"$TEST_TMP/home/.config/moltbook/credentials.json"
    run_cli_without_env_key "" home
    assert_eq 0 "$LAST_STATUS" "loads API key from credentials file"
    assert_eq "Authorization: Bearer file-key" "$(last_request_field auth)" "uses credentials file API key"
}

test_get_commands() {
    setup_test
    run_cli "" home
    assert_last_request "GET" "/home" "home"

    setup_test
    run_cli "" feed new 10 unread
    assert_last_request "GET" "/feed?sort=new&limit=10&filter=unread" "feed with options"

    setup_test
    run_cli "" feed
    assert_last_request "GET" "/feed?sort=hot&limit=25&filter=all" "feed defaults"

    setup_test
    run_cli "" explore top 5 general
    assert_last_request "GET" "/posts?sort=top&limit=5&submolt=general" "explore with submolt"

    setup_test
    run_cli "" explore
    assert_last_request "GET" "/posts?sort=hot&limit=25" "explore defaults"

    setup_test
    run_cli "" comments p123 new 2
    assert_last_request "GET" "/posts/p123/comments?sort=new&limit=2" "comments with options"
}

test_read_resource_commands() {
    setup_test
    run_cli "" me
    assert_last_request "GET" "/agents/me" "me"

    setup_test
    run_cli "" status
    assert_last_request "GET" "/agents/status" "status"

    setup_test
    run_cli "" get-post abc
    assert_last_request "GET" "/posts/abc" "get-post"

    setup_test
    run_cli "" submolts
    assert_last_request "GET" "/submolts" "submolts"

    setup_test
    run_cli "" submolt general
    assert_last_request "GET" "/submolts/general" "submolt"

    setup_test
    run_cli "" moderators general
    assert_last_request "GET" "/submolts/general/moderators" "moderators"

    setup_test
    run_cli "" profile alice
    assert_last_request "GET" "/agents/profile?name=alice" "profile"

    setup_test
    run_cli "" dm-check
    assert_last_request "GET" "/agents/dm/check" "dm-check"

    setup_test
    run_cli "" dm-requests
    assert_last_request "GET" "/agents/dm/requests" "dm-requests"

    setup_test
    run_cli "" dm-conversations
    assert_last_request "GET" "/agents/dm/conversations" "dm-conversations"

    setup_test
    run_cli "" dm-conversation c1
    assert_last_request "GET" "/agents/dm/conversations/c1" "dm-conversation"
}

test_write_without_prompts() {
    setup_test
    run_cli "" delete-post p1
    assert_last_request "DELETE" "/posts/p1" "delete-post"

    setup_test
    run_cli "" pin-post p1
    assert_last_request "POST" "/posts/p1/pin" "pin-post"
    assert_json_eq '{}' "$(last_request_data)" "pin-post sends empty JSON"

    setup_test
    run_cli "" unpin-post p1
    assert_last_request "DELETE" "/posts/p1/pin" "unpin-post"

    setup_test
    run_cli "" upvote-post p1
    assert_last_request "POST" "/posts/p1/upvote" "upvote-post"

    setup_test
    run_cli "" downvote-post p1
    assert_last_request "POST" "/posts/p1/downvote" "downvote-post"

    setup_test
    run_cli "" upvote-comment c1
    assert_last_request "POST" "/comments/c1/upvote" "upvote-comment"

    setup_test
    run_cli "" subscribe general
    assert_last_request "POST" "/submolts/general/subscribe" "subscribe"

    setup_test
    run_cli "" unsubscribe general
    assert_last_request "DELETE" "/submolts/general/subscribe" "unsubscribe"

    setup_test
    run_cli "" follow alice
    assert_last_request "POST" "/agents/alice/follow" "follow"

    setup_test
    run_cli "" unfollow alice
    assert_last_request "DELETE" "/agents/alice/follow" "unfollow"

    setup_test
    run_cli "" mark-read p1
    assert_last_request "POST" "/notifications/read-by-post/p1" "mark-read"

    setup_test
    run_cli "" mark-all-read
    assert_last_request "POST" "/notifications/read-all" "mark-all-read"

    setup_test
    run_cli "" dm-approve c1
    assert_last_request "POST" "/agents/dm/requests/c1/approve" "dm-approve"

    setup_test
    run_cli "" dm-reject c1 true
    assert_last_request "POST" "/agents/dm/requests/c1/reject" "dm-reject block"
    assert_json_eq '{"block":true}' "$(last_request_data)" "dm-reject true sends block"

    setup_test
    run_cli "" dm-reject c1
    assert_last_request "POST" "/agents/dm/requests/c1/reject" "dm-reject default"
    assert_json_eq '{}' "$(last_request_data)" "dm-reject default sends empty JSON"
}

test_prompted_payloads() {
    setup_test
    run_cli $'custom\nA title\nLine 1\nLine 2\n.\n' post
    assert_last_request "POST" "/posts" "post"
    assert_json_eq '{"submolt_name":"custom","title":"A title","content":"Line 1\nLine 2","type":"text"}' "$(last_request_data)" "post payload"

    setup_test
    run_cli $'\nA link\nhttps://example.test/a?b=1\n' link
    assert_last_request "POST" "/posts" "link"
    assert_json_eq '{"submolt_name":"general","title":"A link","url":"https://example.test/a?b=1","type":"link"}' "$(last_request_data)" "link payload defaults submolt"

    setup_test
    run_cli $'Nice post\n' comment p1
    assert_last_request "POST" "/posts/p1/comments" "comment"
    assert_json_eq '{"content":"Nice post"}' "$(last_request_data)" "comment payload"

    setup_test
    run_cli $'c0\nNested reply\n' reply p1
    assert_last_request "POST" "/posts/p1/comments" "reply"
    assert_json_eq '{"content":"Nested reply","parent_id":"c0"}' "$(last_request_data)" "reply payload"

    setup_test
    run_cli $'general\nGeneral\nA place\ntrue\n' create-submolt
    assert_last_request "POST" "/submolts" "create-submolt"
    assert_json_eq '{"name":"general","display_name":"General","description":"A place","allow_crypto":true}' "$(last_request_data)" "create-submolt payload"

    setup_test
    run_cli $'New description\n#112233\n#445566\n' submolt-settings general
    assert_last_request "PATCH" "/submolts/general/settings" "submolt-settings"
    assert_json_eq '{"description":"New description","banner_color":"#112233","theme_color":"#445566"}' "$(last_request_data)" "submolt-settings payload"

    setup_test
    run_cli $'bob\nadmin\n' add-moderator general
    assert_last_request "POST" "/submolts/general/moderators" "add-moderator"
    assert_json_eq '{"agent_name":"bob","role":"admin"}' "$(last_request_data)" "add-moderator payload"

    setup_test
    run_cli $'bob\n' remove-moderator general
    assert_last_request "DELETE" "/submolts/general/moderators" "remove-moderator"
    assert_json_eq '{"agent_name":"bob"}' "$(last_request_data)" "remove-moderator payload"

    setup_test
    run_cli $'Updated profile\n' update-profile
    assert_last_request "PATCH" "/agents/me" "update-profile"
    assert_json_eq '{"description":"Updated profile"}' "$(last_request_data)" "update-profile payload"

    setup_test
    run_cli $'owner@example.test\n' setup-owner-email
    assert_last_request "POST" "/agents/me/setup-owner-email" "setup-owner-email"
    assert_json_eq '{"email":"owner@example.test"}' "$(last_request_data)" "setup-owner-email payload"

    setup_test
    run_cli $'hello world/@me\nposts\n7\n' search
    assert_last_request "GET" "/search?q=hello%20world/%40me&type=posts&limit=7" "search encodes query"

    setup_test
    run_cli $'alice\nHi there\n' dm-request
    assert_last_request "POST" "/agents/dm/request" "dm-request by bot name"
    assert_json_eq '{"to":"alice","message":"Hi there"}' "$(last_request_data)" "dm-request bot payload"

    setup_test
    run_cli $'\n@owner\nHello owner\n' dm-request
    assert_last_request "POST" "/agents/dm/request" "dm-request by owner handle"
    assert_json_eq '{"to_owner":"@owner","message":"Hello owner"}' "$(last_request_data)" "dm-request owner payload"

    setup_test
    run_cli $'Need help\ntrue\n' dm-send c1
    assert_last_request "POST" "/agents/dm/conversations/c1/send" "dm-send needs human"
    assert_json_eq '{"message":"Need help","needs_human_input":true}' "$(last_request_data)" "dm-send human payload"

    setup_test
    run_cli $'Automated reply\n\n' dm-send c1
    assert_last_request "POST" "/agents/dm/conversations/c1/send" "dm-send default"
    assert_json_eq '{"message":"Automated reply"}' "$(last_request_data)" "dm-send default payload"
}

test_required_arguments() {
    local commands=(
	"get-post Missing post_id"
	"delete-post Missing post_id"
	"pin-post Missing post_id"
	"unpin-post Missing post_id"
	"comments Missing post_id"
	"comment Missing post_id"
	"reply Missing post_id"
	"upvote-post Missing post_id"
	"downvote-post Missing post_id"
	"upvote-comment Missing comment_id"
	"submolt Missing submolt name"
	"subscribe Missing submolt name"
	"unsubscribe Missing submolt name"
	"submolt-settings Missing submolt name"
	"moderators Missing submolt name"
	"add-moderator Missing submolt name"
	"remove-moderator Missing submolt name"
	"profile Missing agent name"
	"follow Missing molty name"
	"unfollow Missing molty name"
	"mark-read Missing post_id"
	"dm-approve Missing conversation_id"
	"dm-reject Missing conversation_id"
	"dm-conversation Missing conversation_id"
	"dm-send Missing conversation_id"
    )

    local item command message
    for item in "${commands[@]}"; do
	setup_test
	command="${item%% *}"
	message="${item#* }"
	run_cli "" "$command"
	assert_eq 1 "$LAST_STATUS" "$command without required argument exits with failure"
	assert_contains "$LAST_ERR" "$message" "$command missing argument message"
	assert_eq 0 "$(request_count)" "$command missing argument does not call curl"
    done
}

test_verification_flow() {
    setup_test
    export FAKE_CURL_CHALLENGE_SUFFIX="/posts"
    export FAKE_CURL_CHALLENGE_RESPONSE='{"post":{"verification":{"verification_code":"code-1"}}}'
    export FAKE_CURL_VERIFY_RESPONSE='{"verified":true}'
    run_cli $'general\nNeeds verify\nBody\n.\n42\n' post

    assert_eq 0 "$LAST_STATUS" "verification flow exits successfully"
    assert_eq 2 "$(request_count)" "verification flow makes two requests"
    assert_eq "https://www.moltbook.com/api/v1/posts" "$(request_field 1 url)" "verification first request posts URL"
    assert_eq "https://www.moltbook.com/api/v1/verify" "$(request_field 2 url)" "verification second request URL"
    assert_json_eq '{"verification_code":"code-1","answer":"42"}' "$(request_json 2 | jq -r '.data | fromjson | tojson')" "verification payload"
}

test_syntax() {
    TEST_COUNT=$((TEST_COUNT + 1))
    if bash -n "$SCRIPT"; then
	pass "moltbook.sh passes bash syntax check"
    else
	fail "moltbook.sh passes bash syntax check"
    fi

    TEST_COUNT=$((TEST_COUNT + 1))
    if bash -n "$ROOT_DIR/tests/run_tests.sh"; then
	pass "test runner passes bash syntax check"
    else
	fail "test runner passes bash syntax check"
    fi
}

test_help_and_auth
test_get_commands
test_read_resource_commands
test_write_without_prompts
test_prompted_payloads
test_required_arguments
test_verification_flow
test_syntax

printf '\n%d tests, %d failures\n' "$TEST_COUNT" "$FAIL_COUNT"
if ((FAIL_COUNT > 0)); then
    exit 1
fi
