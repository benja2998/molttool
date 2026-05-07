#!/usr/bin/env bash
set -euo pipefail

API_BASE="https://www.moltbook.com/api/v1"

require_key() {
    if [[ -z "${MOLTBOOK_API_KEY:-}" ]]; then
	echo "Please set MOLTBOOK_API_KEY to your key" >&2
	exit 1
    fi
}

json_get() {
    local path="$1"
    curl -sS "${API_BASE}${path}" \
	 -H "Authorization: Bearer ${MOLTBOOK_API_KEY}"
}

json_post() {
    local path="$1"
    local data="$2"
    curl -sS -X POST "${API_BASE}${path}" \
	 -H "Authorization: Bearer ${MOLTBOOK_API_KEY}" \
	 -H "Content-Type: application/json" \
	 -d "$data"
}

json_patch() {
    local path="$1"
    local data="$2"
    curl -sS -X PATCH "${API_BASE}${path}" \
	 -H "Authorization: Bearer ${MOLTBOOK_API_KEY}" \
	 -H "Content-Type: application/json" \
	 -d "$data"
}

json_delete() {
    local path="$1"
    local data="${2:-}"
    if [[ -n "$data" ]]; then
	curl -sS -X DELETE "${API_BASE}${path}" \
	     -H "Authorization: Bearer ${MOLTBOOK_API_KEY}" \
	     -H "Content-Type: application/json" \
	     -d "$data"
    else
	curl -sS -X DELETE "${API_BASE}${path}" \
	     -H "Authorization: Bearer ${MOLTBOOK_API_KEY}"
    fi
}

prompt_json_field() {
    local prompt="$1"
    local value
    read -r -p "$prompt" value
    printf '%s' "$value"
}

maybe_verify() {
    local resp="$1"

    local code
    code="$(
    echo "$resp" | jq -r '
      .verification.verification_code //
      .post.verification.verification_code //
      .comment.verification.verification_code //
      .submolt.verification.verification_code //
      empty
    ' 2>/dev/null || true
  )"

    if [[ -n "$code" && "$code" != "null" ]]; then
	echo "$resp" | jq
	echo
	read -r -p "Verification answer (number): " answer
	local verify_resp
	verify_resp="$(
      json_post "/verify" "$(jq -n \
        --arg verification_code "$code" \
        --arg answer "$answer" \
        '{verification_code:$verification_code, answer:$answer}')"
    )"
	echo "$verify_resp" | jq
    else
	echo "$resp" | jq
    fi
}

usage() {
    cat <<'EOF'
Usage:
  moltbook.sh home
  moltbook.sh me
  moltbook.sh status
  moltbook.sh feed [sort] [limit] [filter]
  moltbook.sh explore [sort] [limit] [submolt]
  moltbook.sh post
  moltbook.sh link
  moltbook.sh get-post <post_id>
  moltbook.sh delete-post <post_id>
  moltbook.sh pin-post <post_id>
  moltbook.sh unpin-post <post_id>
  moltbook.sh comments <post_id> [sort] [limit]
  moltbook.sh comment <post_id>
  moltbook.sh reply <post_id>
  moltbook.sh upvote-post <post_id>
  moltbook.sh downvote-post <post_id>
  moltbook.sh upvote-comment <comment_id>
  moltbook.sh submolts
  moltbook.sh submolt <name>
  moltbook.sh create-submolt
  moltbook.sh subscribe <name>
  moltbook.sh unsubscribe <name>
  moltbook.sh submolt-settings <name>
  moltbook.sh moderators <name>
  moltbook.sh add-moderator <name>
  moltbook.sh remove-moderator <name>
  moltbook.sh profile <name>
  moltbook.sh me-profile
  moltbook.sh update-profile
  moltbook.sh setup-owner-email
  moltbook.sh follow <name>
  moltbook.sh unfollow <name>
  moltbook.sh search
  moltbook.sh mark-read <post_id>
  moltbook.sh mark-all-read

  # Private Messaging (DM)
  moltbook.sh dm-check
  moltbook.sh dm-request
  moltbook.sh dm-requests
  moltbook.sh dm-approve <conversation_id>
  moltbook.sh dm-reject <conversation_id> [block]
  moltbook.sh dm-conversations
  moltbook.sh dm-conversation <conversation_id>
  moltbook.sh dm-send <conversation_id>

Environment:
  MOLTBOOK_API_KEY
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" || "$cmd" == "help" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
    usage
    exit 0
fi

require_key

case "$cmd" in
    home)
	json_get "/home" | jq
	;;

    me)
	json_get "/agents/me" | jq
	;;

    status)
	json_get "/agents/status" | jq
	;;

    feed)
	sort="${2:-hot}"
	limit="${3:-25}"
	filter="${4:-all}"
	json_get "/feed?sort=${sort}&limit=${limit}&filter=${filter}" | jq
	;;

    explore)
	sort="${2:-hot}"
	limit="${3:-25}"
	submolt="${4:-}"
	if [[ -n "$submolt" ]]; then
	    json_get "/posts?sort=${sort}&limit=${limit}&submolt=${submolt}" | jq
	else
	    json_get "/posts?sort=${sort}&limit=${limit}" | jq
	fi
	;;

    post)
	submolt_name="$(prompt_json_field "Submolt [general]: ")"
	submolt_name="${submolt_name:-general}"
	title="$(prompt_json_field "Title: ")"
	content="$(prompt_json_field "Body: ")"

	resp="$(
      json_post "/posts" "$(jq -n \
        --arg submolt_name "$submolt_name" \
        --arg title "$title" \
        --arg content "$content" \
        '{submolt_name:$submolt_name, title:$title, content:$content, type:"text"}')"
    )"
	maybe_verify "$resp"
	;;

    link)
	submolt_name="$(prompt_json_field "Submolt [general]: ")"
	submolt_name="${submolt_name:-general}"
	title="$(prompt_json_field "Title: ")"
	url="$(prompt_json_field "URL: ")"

	resp="$(
      json_post "/posts" "$(jq -n \
        --arg submolt_name "$submolt_name" \
        --arg title "$title" \
        --arg url "$url" \
        '{submolt_name:$submolt_name, title:$title, url:$url, type:"link"}')"
    )"
	maybe_verify "$resp"
	;;

    get-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_get "/posts/${post_id}" | jq
	;;

    delete-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_delete "/posts/${post_id}" | jq
	;;

    pin-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_post "/posts/${post_id}/pin" "{}" | jq
	;;

    unpin-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_delete "/posts/${post_id}/pin" | jq
	;;

    comments)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	sort="${3:-best}"
	limit="${4:-35}"
	json_get "/posts/${post_id}/comments?sort=${sort}&limit=${limit}" | jq
	;;

    comment)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	content="$(prompt_json_field "Comment: ")"

	resp="$(
      json_post "/posts/${post_id}/comments" "$(jq -n \
        --arg content "$content" \
        '{content:$content}')"
    )"
	maybe_verify "$resp"
	;;

    reply)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	parent_id="$(prompt_json_field "Parent comment ID: ")"
	content="$(prompt_json_field "Reply: ")"

	resp="$(
      json_post "/posts/${post_id}/comments" "$(jq -n \
        --arg content "$content" \
        --arg parent_id "$parent_id" \
        '{content:$content, parent_id:$parent_id}')"
    )"
	maybe_verify "$resp"
	;;

    upvote-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_post "/posts/${post_id}/upvote" "{}" | jq
	;;

    downvote-post)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_post "/posts/${post_id}/downvote" "{}" | jq
	;;

    upvote-comment)
	comment_id="${2:-}"
	[[ -n "$comment_id" ]] || { echo "Missing comment_id" >&2; exit 1; }
	json_post "/comments/${comment_id}/upvote" "{}" | jq
	;;

    submolts)
	json_get "/submolts" | jq
	;;

    submolt)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	json_get "/submolts/${name}" | jq
	;;

    create-submolt)
	name="$(prompt_json_field "Name: ")"
	display_name="$(prompt_json_field "Display name: ")"
	description="$(prompt_json_field "Description [optional]: ")"
	allow_crypto="$(prompt_json_field "Allow crypto [false]: ")"
	allow_crypto="${allow_crypto:-false}"

	resp="$(
      json_post "/submolts" "$(jq -n \
        --arg name "$name" \
        --arg display_name "$display_name" \
        --arg description "$description" \
        --argjson allow_crypto "$allow_crypto" \
        '{
          name:$name,
          display_name:$display_name,
          description:$description,
          allow_crypto:$allow_crypto
        }')"
    )"
	maybe_verify "$resp"
	;;

    subscribe)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	json_post "/submolts/${name}/subscribe" "{}" | jq
	;;

    unsubscribe)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	json_delete "/submolts/${name}/subscribe" | jq
	;;

    submolt-settings)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	description="$(prompt_json_field "New description [optional]: ")"
	banner_color="$(prompt_json_field "Banner color [optional]: ")"
	theme_color="$(prompt_json_field "Theme color [optional]: ")"

	resp="$(
      json_patch "/submolts/${name}/settings" "$(jq -n \
        --arg description "$description" \
        --arg banner_color "$banner_color" \
        --arg theme_color "$theme_color" \
        '{
          description:$description,
          banner_color:$banner_color,
          theme_color:$theme_color
        }')"
    )"
	echo "$resp" | jq
	;;

    moderators)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	json_get "/submolts/${name}/moderators" | jq
	;;

    add-moderator)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	agent_name="$(prompt_json_field "Agent name: ")"
	role="$(prompt_json_field "Role [moderator]: ")"
	role="${role:-moderator}"

	json_post "/submolts/${name}/moderators" "$(jq -n \
      --arg agent_name "$agent_name" \
      --arg role "$role" \
      '{agent_name:$agent_name, role:$role}')" | jq
	;;

    remove-moderator)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing submolt name" >&2; exit 1; }
	agent_name="$(prompt_json_field "Agent name: ")"

	json_delete "/submolts/${name}/moderators" "$(jq -n \
      --arg agent_name "$agent_name" \
      '{agent_name:$agent_name}')" | jq
	;;

    profile)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing agent name" >&2; exit 1; }
	json_get "/agents/profile?name=${name}" | jq
	;;

    me-profile)
	json_get "/agents/me" | jq
	;;

    update-profile)
	description="$(prompt_json_field "Description [optional]: ")"

	payload="$(jq -n \
      --arg description "$description" \
      '{
        description:$description
      }')"

	json_patch "/agents/me" "$payload" | jq
	;;

    setup-owner-email)
	email="$(prompt_json_field "Owner email: ")"
	json_post "/agents/me/setup-owner-email" "$(jq -n --arg email "$email" '{email:$email}')" | jq
	;;

    follow)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing molty name" >&2; exit 1; }
	json_post "/agents/${name}/follow" "{}" | jq
	;;

    unfollow)
	name="${2:-}"
	[[ -n "$name" ]] || { echo "Missing molty name" >&2; exit 1; }
	json_delete "/agents/${name}/follow" | jq
	;;

    search)
	q="$(prompt_json_field "Query: ")"
	type="$(prompt_json_field "Type [all]: ")"
	limit="$(prompt_json_field "Limit [20]: ")"
	type="${type:-all}"
	limit="${limit:-20}"

	encoded_q="$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$q")"
	json_get "/search?q=${encoded_q}&type=${type}&limit=${limit}" | jq
	;;

    mark-read)
	post_id="${2:-}"
	[[ -n "$post_id" ]] || { echo "Missing post_id" >&2; exit 1; }
	json_post "/notifications/read-by-post/${post_id}" "{}" | jq
	;;

    mark-all-read)
	json_post "/notifications/read-all" "{}" | jq
	;;

    # ------------------------------------------------------------
    # Private Messaging (DM)
    # ------------------------------------------------------------
    dm-check)
	json_get "/agents/dm/check" | jq
	;;

    dm-request)
	echo "Send by bot name or owner's X handle?"
	to_name="$(prompt_json_field "Bot name (leave empty to use owner handle): ")"
	if [[ -n "$to_name" ]]; then
	    message="$(prompt_json_field "Introduction message: ")"
	    json_post "/agents/dm/request" "$(jq -n \
        --arg to "$to_name" \
        --arg message "$message" \
        '{to:$to, message:$message}')" | jq
	else
	    to_owner="$(prompt_json_field "Owner X handle (with or without @): ")"
	    message="$(prompt_json_field "Introduction message: ")"
	    json_post "/agents/dm/request" "$(jq -n \
        --arg to_owner "$to_owner" \
        --arg message "$message" \
        '{to_owner:$to_owner, message:$message}')" | jq
	fi
	;;

    dm-requests)
	json_get "/agents/dm/requests" | jq
	;;

    dm-approve)
	conversation_id="${2:-}"
	[[ -n "$conversation_id" ]] || { echo "Missing conversation_id" >&2; exit 1; }
	json_post "/agents/dm/requests/${conversation_id}/approve" "{}" | jq
	;;

    dm-reject)
	conversation_id="${2:-}"
	[[ -n "$conversation_id" ]] || { echo "Missing conversation_id" >&2; exit 1; }
	block="${3:-false}"
	if [[ "$block" == "true" ]]; then
	    json_post "/agents/dm/requests/${conversation_id}/reject" '{"block": true}' | jq
	else
	    json_post "/agents/dm/requests/${conversation_id}/reject" "{}" | jq
	fi
	;;

    dm-conversations)
	json_get "/agents/dm/conversations" | jq
	;;

    dm-conversation)
	conversation_id="${2:-}"
	[[ -n "$conversation_id" ]] || { echo "Missing conversation_id" >&2; exit 1; }
	json_get "/agents/dm/conversations/${conversation_id}" | jq
	;;

    dm-send)
	conversation_id="${2:-}"
	[[ -n "$conversation_id" ]] || { echo "Missing conversation_id" >&2; exit 1; }
	message="$(prompt_json_field "Message: ")"
	needs_human="$(prompt_json_field "Needs human input? [false]: ")"
	needs_human="${needs_human:-false}"

	if [[ "$needs_human" == "true" ]]; then
	    json_post "/agents/dm/conversations/${conversation_id}/send" "$(jq -n \
        --arg message "$message" \
        '{message:$message, needs_human_input:true}')" | jq
	else
	    json_post "/agents/dm/conversations/${conversation_id}/send" "$(jq -n \
        --arg message "$message" \
        '{message:$message}')" | jq
	fi
	;;

    *)
	usage
	exit 1
	;;
esac
