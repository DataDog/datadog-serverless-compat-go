#!/usr/bin/env bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2026-present Datadog, Inc.

set -euo pipefail

readonly OWNER="DataDog"
readonly REPOSITORY="DataDog/datadog-serverless-compat-go"
readonly MODULE_DIR="datadogserverlesscompat"
readonly VERSION_FILE="$MODULE_DIR/datadog_serverless_compat.go"
readonly EMBEDDED_BINARY="$MODULE_DIR/internal/bin/linux-amd64/datadog-serverless-compat"
readonly CORE_REPOSITORY="DataDog/serverless-components"
readonly CORE_TAG="datadog-serverless-compat/v${CORE_VERSION}"
readonly RELEASE_BRANCH="release/serverless-compat-v${PACKAGE_VERSION}"
readonly MODULE_TAG="datadogserverlesscompat/v${PACKAGE_VERSION}"
readonly PR_TITLE="Release datadogserverlesscompat/v${PACKAGE_VERSION}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

remote_branch_sha() {
  git ls-remote --heads origin "refs/heads/$1" | awk 'NR == 1 { print $1 }'
}

remote_tag_sha() {
  local lines peeled direct
  lines="$(git ls-remote --tags origin "refs/tags/$1" "refs/tags/$1^{}")"
  peeled="$(printf '%s\n' "$lines" | awk '$2 ~ /\^\{\}$/ { print $1; exit }')"
  direct="$(printf '%s\n' "$lines" | awk '$2 !~ /\^\{\}$/ { print $1; exit }')"
  printf '%s\n' "${peeled:-$direct}"
}

download_core_binary() {
  local encoded_tag release_json asset_count asset_url
  encoded_tag="$(jq -rn --arg value "$CORE_TAG" '$value | @uri')"
  release_json="$TMP_DIR/core-release.json"

  curl --fail-with-body --silent --show-error \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$CORE_REPOSITORY/releases/tags/$encoded_tag" \
    > "$release_json"

  [[ "$(jq -r '.tag_name' "$release_json")" == "$CORE_TAG" ]] || fail "core Release tag does not match $CORE_TAG"
  [[ "$(jq -r '.draft' "$release_json")" == "false" ]] || fail "core Release $CORE_TAG is not published"

  asset_count="$(jq '[.assets[] | select(.name == "datadog-serverless-compat.zip" and .state == "uploaded")] | length' "$release_json")"
  [[ "$asset_count" == "1" ]] || fail "core Release must have exactly one uploaded datadog-serverless-compat.zip asset"
  asset_url="$(jq -r '.assets[] | select(.name == "datadog-serverless-compat.zip" and .state == "uploaded") | .browser_download_url' "$release_json")"

  curl --fail-with-body --silent --show-error --location \
    "$asset_url" \
    --output "$TMP_DIR/datadog-serverless-compat.zip"
  unzip -q "$TMP_DIR/datadog-serverless-compat.zip" -d "$TMP_DIR/core"
  [[ -f "$TMP_DIR/core/bin/linux-amd64/datadog-serverless-compat" ]] || fail "core ZIP is missing bin/linux-amd64/datadog-serverless-compat"

  CORE_BINARY="$TMP_DIR/core/bin/linux-amd64/datadog-serverless-compat"
  CORE_BINARY_SHA256="$(sha256sum "$CORE_BINARY" | awk '{ print $1 }')"
  readonly CORE_BINARY CORE_BINARY_SHA256
}

block_other_reconciliation_prs() {
  local pulls other_count
  pulls="$(gh api --paginate -X GET "repos/$REPOSITORY/pulls" \
    -f state=open -f base=main -f per_page=100 | jq -s 'add')"
  other_count="$(jq --arg branch "$RELEASE_BRANCH" \
    '[.[] | select(.head.ref | startswith("release/serverless-compat-v")) | select(.head.ref != $branch)] | length' \
    <<< "$pulls")"
  [[ "$other_count" == "0" ]] || {
    jq -r --arg branch "$RELEASE_BRANCH" \
      '.[] | select(.head.ref | startswith("release/serverless-compat-v")) | select(.head.ref != $branch) | "Open reconciliation PR #\(.number): \(.html_url)"' \
      <<< "$pulls" >&2
    fail "a previous reconciliation PR must be merged before preparing another release"
  }
}

get_reconciliation_pr() {
  local pulls count
  pulls="$(gh api --paginate -X GET "repos/$REPOSITORY/pulls" \
    -f state=all -f head="$OWNER:$RELEASE_BRANCH" -f per_page=100 | jq -s 'add')"
  count="$(jq 'length' <<< "$pulls")"
  [[ "$count" -le 1 ]] || fail "multiple reconciliation PRs use $RELEASE_BRANCH"
  if [[ "$count" == "1" ]]; then
    PR_JSON="$(jq '.[0]' <<< "$pulls")"
  else
    PR_JSON=""
  fi
}

pr_body() {
  local prepared_operation="${1:-$OPERATION_ID}"
  cat <<EOF
Reconciles the published Go module source with \`main\`.

Package version: v${PACKAGE_VERSION}
Core version: ${CORE_TAG}
Base commit: ${BASE_SHA}
Release commit: ${RELEASE_SHA}
Binary SHA-256: ${BINARY_SHA256}
Prepared by operation: ${prepared_operation}
EOF
}

release_body() {
  local prepared_operation="$1"
  cat <<EOF
Uses [${CORE_TAG}](https://github.com/DataDog/serverless-components/releases/tag/${CORE_TAG}) of the Serverless Compatibility Layer binary.

Package version: v${PACKAGE_VERSION}
Core version: ${CORE_TAG}
Base commit: ${BASE_SHA}
Release commit: ${RELEASE_SHA}
Binary SHA-256: ${BINARY_SHA256}
Reconciliation PR: ${PR_URL}
Prepared by operation: ${prepared_operation}
EOF
}

require_body_line() {
  local body="$1" expected="$2"
  grep -Fqx -- "$expected" <<< "$body" || fail "release metadata is missing or conflicts: $expected"
}

validate_pr() {
  local body state merged_at prepared_lines
  [[ -n "$PR_JSON" ]] || fail "reconciliation PR for $RELEASE_BRANCH does not exist"
  [[ "$(jq -r '.head.repo.full_name' <<< "$PR_JSON")" == "$REPOSITORY" ]] || fail "reconciliation PR head repository conflicts"
  [[ "$(jq -r '.head.ref' <<< "$PR_JSON")" == "$RELEASE_BRANCH" ]] || fail "reconciliation PR head branch conflicts"
  [[ "$(jq -r '.head.sha' <<< "$PR_JSON")" == "$RELEASE_SHA" ]] || fail "reconciliation PR head commit conflicts"
  [[ "$(jq -r '.base.ref' <<< "$PR_JSON")" == "main" ]] || fail "reconciliation PR base branch conflicts"
  [[ "$(jq -r '.title' <<< "$PR_JSON")" == "$PR_TITLE" ]] || fail "reconciliation PR title conflicts"

  state="$(jq -r '.state' <<< "$PR_JSON")"
  merged_at="$(jq -r '.merged_at // empty' <<< "$PR_JSON")"
  [[ "$state" == "open" || -n "$merged_at" ]] || fail "reconciliation PR was closed without merging"

  body="$(jq -r '.body // ""' <<< "$PR_JSON")"
  require_body_line "$body" "Package version: v${PACKAGE_VERSION}"
  require_body_line "$body" "Core version: ${CORE_TAG}"
  require_body_line "$body" "Base commit: ${BASE_SHA}"
  require_body_line "$body" "Release commit: ${RELEASE_SHA}"
  require_body_line "$body" "Binary SHA-256: ${BINARY_SHA256}"
  prepared_lines="$(grep -Ec '^Prepared by operation: [0-9A-Za-z][0-9A-Za-z._-]{0,127}$' <<< "$body")"
  [[ "$prepared_lines" == "1" ]] || fail "reconciliation PR has invalid preparation operation metadata"

  PREPARED_OPERATION="$(sed -n 's/^Prepared by operation: //p' <<< "$body")"
  [[ "$body" == "$(pr_body "$PREPARED_OPERATION")" ]] || fail "reconciliation PR body conflicts with the expected release metadata"
  PR_URL="$(jq -r '.html_url' <<< "$PR_JSON")"
  readonly PREPARED_OPERATION PR_URL
}

get_release() {
  local releases count
  releases="$(gh api --paginate -X GET "repos/$REPOSITORY/releases" \
    -f per_page=100 | jq -s --arg tag "$MODULE_TAG" 'add | map(select(.tag_name == $tag))')"
  count="$(jq 'length' <<< "$releases")"
  [[ "$count" -le 1 ]] || fail "multiple GitHub Releases use $MODULE_TAG"
  if [[ "$count" == "1" ]]; then
    RELEASE_JSON="$(jq '.[0]' <<< "$releases")"
  else
    RELEASE_JSON=""
  fi
}

validate_release() {
  local body prepared_line published_line asset_count expected_body
  [[ -n "$RELEASE_JSON" ]] || fail "GitHub Release for $MODULE_TAG does not exist"
  [[ "$(jq -r '.tag_name' <<< "$RELEASE_JSON")" == "$MODULE_TAG" ]] || fail "GitHub Release tag conflicts"
  [[ "$(jq -r '.target_commitish' <<< "$RELEASE_JSON")" == "$RELEASE_SHA" ]] || fail "GitHub Release target commit conflicts"
  [[ "$(jq -r '.name' <<< "$RELEASE_JSON")" == "v${PACKAGE_VERSION}" ]] || fail "GitHub Release name conflicts"
  [[ "$(jq -r '.prerelease' <<< "$RELEASE_JSON")" == "false" ]] || fail "GitHub Release prerelease state conflicts"
  asset_count="$(jq '.assets | length' <<< "$RELEASE_JSON")"
  [[ "$asset_count" == "0" ]] || fail "Go GitHub Release has unexpected assets"

  body="$(jq -r '.body // ""' <<< "$RELEASE_JSON")"
  require_body_line "$body" "Package version: v${PACKAGE_VERSION}"
  require_body_line "$body" "Core version: ${CORE_TAG}"
  require_body_line "$body" "Base commit: ${BASE_SHA}"
  require_body_line "$body" "Release commit: ${RELEASE_SHA}"
  require_body_line "$body" "Binary SHA-256: ${BINARY_SHA256}"
  require_body_line "$body" "Reconciliation PR: ${PR_URL}"
  require_body_line "$body" "Prepared by operation: ${PREPARED_OPERATION}"
  prepared_line="$(grep -Ec '^Prepared by operation: ' <<< "$body")"
  [[ "$prepared_line" == "1" ]] || fail "GitHub Release has conflicting preparation metadata"
  published_line="$(grep -Ec '^Published by operation: [0-9A-Za-z][0-9A-Za-z._-]{0,127}$' <<< "$body" || true)"
  [[ "$published_line" -le 1 ]] || fail "GitHub Release has conflicting publication metadata"
  expected_body="$(release_body "$PREPARED_OPERATION")"
  if [[ "$published_line" == "1" ]]; then
    expected_body="${expected_body}"$'\n'"$(grep '^Published by operation: ' <<< "$body")"
  fi
  [[ "$body" == "$expected_body" ]] || fail "GitHub Release body conflicts with the expected release metadata"
}

validate_release_commit() {
  local parents source_version subject
  git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null || fail "base commit does not exist"
  git cat-file -e "$RELEASE_SHA^{commit}" 2>/dev/null || fail "release commit does not exist"
  parents="$(git rev-list --parents -n 1 "$RELEASE_SHA")"
  [[ "$parents" == "$RELEASE_SHA $BASE_SHA" ]] || fail "release branch must contain exactly one commit on the immutable base"
  subject="$(git log -1 --format=%s "$RELEASE_SHA")"
  [[ "$subject" == "Release datadogserverlesscompat/v${PACKAGE_VERSION} with core v${CORE_VERSION}" ]] || fail "release commit metadata conflicts"
  git diff --quiet "$BASE_SHA" "$RELEASE_SHA" -- . ":(exclude)$MODULE_DIR" || fail "release commit changes files outside the Go module"

  [[ "$(sed -n 's/^module //p' "$MODULE_DIR/go.mod")" == "github.com/DataDog/datadog-serverless-compat-go/datadogserverlesscompat" ]] || fail "Go module path conflicts"
  source_version="$(sed -n 's/^const Version = "\([^"]*\)"$/\1/p' "$VERSION_FILE")"
  [[ "$source_version" == "v${PACKAGE_VERSION}" ]] || fail "source version conflicts with v${PACKAGE_VERSION}"
  [[ -f "$EMBEDDED_BINARY" ]] || fail "embedded Linux amd64 binary is missing"
  BINARY_SHA256="$(sha256sum "$EMBEDDED_BINARY" | awk '{ print $1 }')"
  readonly BINARY_SHA256
}

prepare_draft() {
  local existing_tag latest_tag branch_sha dispatch_branch_sha expected_pr_body release_payload release_url

  git fetch --no-tags origin main
  git fetch --tags origin
  dispatch_branch_sha="$(remote_branch_sha "$RELEASE_BRANCH")"
  if [[ "$DISPATCH_SHA" != "$BASE_SHA" && "$DISPATCH_SHA" != "$dispatch_branch_sha" ]]; then
    fail "draft dispatch commit is neither the immutable base nor the existing deterministic release branch"
  fi
  git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null || fail "immutable base commit is unavailable"
  git merge-base --is-ancestor "$BASE_SHA" origin/main || fail "immutable base commit is not an ancestor of main"

  block_other_reconciliation_prs

  existing_tag="$(remote_tag_sha "$MODULE_TAG")"
  [[ -z "$existing_tag" ]] || fail "$MODULE_TAG already exists; a draft must not create or reuse the module tag"

  latest_tag="$(git tag --list 'datadogserverlesscompat/v*' --sort=-version:refname | head -n 1)"
  if [[ -n "$latest_tag" ]]; then
    git diff --quiet "$latest_tag" origin/main -- "$MODULE_DIR" || \
      fail "main does not contain the latest released Go module; merge its reconciliation PR first"
  fi

  git checkout --detach "$BASE_SHA"
  download_core_binary
  cp "$CORE_BINARY" "$EMBEDDED_BINARY"
  chmod +x "$EMBEDDED_BINARY"

  [[ "$(grep -Ec '^const Version = "[^"]+"$' "$VERSION_FILE")" == "1" ]] || fail "could not identify the package Version constant"
  sed -i "s/^const Version = \"[^\"]*\"$/const Version = \"v${PACKAGE_VERSION}\"/" "$VERSION_FILE"
  (cd "$MODULE_DIR" && go mod tidy)
  git add -- "$MODULE_DIR"

  branch_sha="$(remote_branch_sha "$RELEASE_BRANCH")"
  if [[ -n "$branch_sha" && "$branch_sha" != "$BASE_SHA" ]]; then
    git fetch origin "refs/heads/$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH"
    RELEASE_SHA="$branch_sha"
    git diff --quiet "$RELEASE_SHA" -- || fail "existing release branch content conflicts with the requested release"
    git reset --hard "$RELEASE_SHA"
  else
    # The dispatcher may create the deterministic branch at BASE_SHA so the
    # workflow can run at an immutable ref. Advancing it is a normal fast-forward.
    git diff --cached --quiet && fail "requested release does not change the module"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config user.name "github-actions[bot]"
    git commit -m "Release datadogserverlesscompat/v${PACKAGE_VERSION} with core v${CORE_VERSION}"
    RELEASE_SHA="$(git rev-parse HEAD)"
  fi
  export RELEASE_SHA

  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "tested release commit has tracked working-tree changes"
  validate_release_commit
  [[ "$BINARY_SHA256" == "$CORE_BINARY_SHA256" ]] || fail "embedded binary differs from the selected core release"
  (cd "$MODULE_DIR" && go test -v ./...)

  if [[ "$branch_sha" != "$RELEASE_SHA" ]]; then
    git push origin "$RELEASE_SHA:refs/heads/$RELEASE_BRANCH"
  fi
  [[ "$(remote_branch_sha "$RELEASE_BRANCH")" == "$RELEASE_SHA" ]] || fail "remote release branch does not name the tested commit"

  get_reconciliation_pr
  if [[ -z "$PR_JSON" ]]; then
    expected_pr_body="$TMP_DIR/pr-body.md"
    pr_body > "$expected_pr_body"
    gh pr create --repo "$REPOSITORY" --base main --head "$RELEASE_BRANCH" \
      --title "$PR_TITLE" --body-file "$expected_pr_body" >/dev/null
    get_reconciliation_pr
  fi
  validate_pr
  [[ "$PREPARED_OPERATION" == "$OPERATION_ID" ]] || fail "existing reconciliation PR belongs to a different preparation operation"

  get_release
  if [[ -z "$RELEASE_JSON" ]]; then
    release_payload="$TMP_DIR/release-payload.json"
    jq -n \
      --arg tag "$MODULE_TAG" \
      --arg target "$RELEASE_SHA" \
      --arg name "v${PACKAGE_VERSION}" \
      --arg body "$(release_body "$OPERATION_ID")" \
      '{tag_name: $tag, target_commitish: $target, name: $name, body: $body, draft: true, prerelease: false}' \
      > "$release_payload"
    gh api --method POST "repos/$REPOSITORY/releases" --input "$release_payload" >/dev/null
    get_release
  fi
  validate_release
  [[ "$(jq -r '.draft' <<< "$RELEASE_JSON")" == "true" ]] || fail "existing GitHub Release is already published"
  [[ "$PREPARED_OPERATION" == "$OPERATION_ID" ]] || fail "existing draft belongs to a different preparation operation"
  [[ -z "$(remote_tag_sha "$MODULE_TAG")" ]] || fail "draft preparation unexpectedly created the module tag"

  release_url="$(jq -r '.html_url' <<< "$RELEASE_JSON")"
  {
    echo "Reconciliation PR: $PR_URL"
    echo "Draft Release: $release_url"
    echo "Tested commit: $RELEASE_SHA"
    echo "Embedded binary SHA-256: $BINARY_SHA256"
  } >> "$GITHUB_STEP_SUMMARY"
}

publish_release() {
  local branch_sha existing_tag draft_state body published_body payload release_url

  git fetch --no-tags origin main
  git fetch --tags origin
  branch_sha="$(remote_branch_sha "$RELEASE_BRANCH")"
  [[ -n "$branch_sha" ]] || fail "prepared release branch $RELEASE_BRANCH does not exist"
  [[ "$DISPATCH_SHA" == "$branch_sha" ]] || fail "published dispatch commit does not equal the prepared release commit"
  git fetch origin "refs/heads/$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH"
  git checkout --detach "$branch_sha"
  RELEASE_SHA="$branch_sha"
  export RELEASE_SHA

  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "prepared release branch has tracked working-tree changes"
  validate_release_commit
  download_core_binary
  [[ "$BINARY_SHA256" == "$CORE_BINARY_SHA256" ]] || fail "prepared embedded binary differs from the selected core release"

  get_reconciliation_pr
  validate_pr
  get_release
  validate_release

  existing_tag="$(remote_tag_sha "$MODULE_TAG")"
  if [[ -n "$existing_tag" ]]; then
    [[ "$existing_tag" == "$RELEASE_SHA" ]] || fail "existing module tag points to $existing_tag instead of $RELEASE_SHA"
  else
    git tag "$MODULE_TAG" "$RELEASE_SHA"
    git push origin "refs/tags/$MODULE_TAG"
  fi
  [[ "$(remote_tag_sha "$MODULE_TAG")" == "$RELEASE_SHA" ]] || fail "remote module tag does not name the tested commit"

  draft_state="$(jq -r '.draft' <<< "$RELEASE_JSON")"
  if [[ "$draft_state" == "true" ]]; then
    body="$(jq -r '.body' <<< "$RELEASE_JSON")"
    [[ "$(grep -Ec '^Published by operation: ' <<< "$body")" == "0" ]] || fail "draft has conflicting publication metadata"
    published_body="${body}"$'\n'"Published by operation: ${OPERATION_ID}"
    payload="$TMP_DIR/publish-payload.json"
    jq -n --arg body "$published_body" '{draft: false, make_latest: "true", body: $body}' > "$payload"
    gh api --method PATCH "repos/$REPOSITORY/releases/$(jq -r '.id' <<< "$RELEASE_JSON")" \
      --input "$payload" >/dev/null
    get_release
    validate_release
  fi

  [[ "$(jq -r '.draft' <<< "$RELEASE_JSON")" == "false" ]] || fail "GitHub Release is still a draft"
  body="$(jq -r '.body // ""' <<< "$RELEASE_JSON")"
  require_body_line "$body" "Published by operation: ${OPERATION_ID}"
  [[ "$(grep -Ec '^Published by operation: ' <<< "$body")" == "1" ]] || fail "GitHub Release has conflicting publication metadata"

  release_url="$(jq -r '.html_url' <<< "$RELEASE_JSON")"
  {
    echo "Reconciliation PR: $PR_URL"
    echo "Published Release: $release_url"
    echo "Module tag: $MODULE_TAG"
    echo "Tested commit: $RELEASE_SHA"
  } >> "$GITHUB_STEP_SUMMARY"
}

case "${1:-}" in
  draft)
    prepare_draft
    ;;
  published)
    publish_release
    ;;
  *)
    fail "usage: $0 {draft|published}"
    ;;
esac
