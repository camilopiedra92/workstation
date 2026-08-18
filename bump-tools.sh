#!/usr/bin/env bash
# Moves every hand-maintained exact version pin in this repo to its current
# upstream release, and keeps everything that has to move with it in the
# same pass.
#
# Two families of pin, one script, because leaving them apart is exactly how
# they drift:
#
#   CI tools (shellcheck, shfmt, actionlint, taplo): a version in
#   .github/workflows/ci.yml's env vars, the same version restated in that
#   file's "Tools are the pinned versions" step, a checksum in
#   .github/tool-checksums.txt, and -- for the three of them the host also
#   runs -- a matching version in windows/configuration.winget. All four move
#   together or CI and the host stop agreeing on what a clean file looks
#   like.
#
#   The mise pins in wsl/mise/config.toml: eleven of them, ten user tools
#   plus gh. There is no checksum for these, so the pass is simpler -- read
#   the latest release, rewrite the pin, leave the reasoning comment alone.
#   Widened into this script for the reason this ruling exists at all: every
#   one of those eleven numbers was wrong when the plan for this repo was
#   written, and one of them -- eza = "0.24.7" -- named a version that was
#   never published. mise install would have failed on the user's machine. A
#   tool whose reason is written down gets used; pinning by hand is what
#   this replaces.
#
# node, python and pnpm in wsl/mise/config.toml are deliberately out of
# scope: they are pinned by major or minor, each with its own reasoning
# written beside it, not by exact version, so there is nothing here for a
# release-following bump to do.
#
# Usage:  ./bump-tools.sh
#
# It never merges anything by itself. The versions it writes are whatever
# upstream is publishing right now, which is precisely what
# tool-checksums.txt says not to trust blindly -- a human reads the diff
# before this reaches CI.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

command -v gh > /dev/null 2>&1 || {
  echo "bump-tools.sh needs the gh CLI to read releases/latest" >&2
  exit 1
}

CI_WORKFLOW=.github/workflows/ci.yml
CI_CHECKSUMS=.github/tool-checksums.txt
HOST_MANIFEST=windows/configuration.winget
MISE_CONFIG=wsl/mise/config.toml

CI_TOOLS="shellcheck shfmt actionlint taplo"
MISE_TOOLS="gh starship eza bat fd ripgrep fzf zoxide jq delta uv"

BOLD=$'\033[1m'
GREEN=$'\033[32m'
DIM=$'\033[90m'
OFF=$'\033[0m'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

changed=0

# An upstream API that answers oddly, or a tag that is a backport of an
# older line, must not walk a pin backwards. Refuse rather than "update"
# into a version with known fixes missing.
newer_or_equal() { # newer_or_equal <have> <want>
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

# ---------------------------------------------------------------------------
# CI tools
# ---------------------------------------------------------------------------

# The env var each tool's version lives in, in ci.yml.
ci_var_of() {
  case "$1" in
    shellcheck) echo SHELLCHECK_VERSION ;;
    shfmt) echo SHFMT_VERSION ;;
    actionlint) echo ACTIONLINT_VERSION ;;
    taplo) echo TAPLO_VERSION ;;
  esac
}

# Latest upstream version, bare -- ci.yml's env vars carry no leading v, even
# for the two tools (shellcheck, shfmt) whose tags do.
ci_latest_of() {
  case "$1" in
    shellcheck) gh api repos/koalaman/shellcheck/releases/latest --jq .tag_name | sed 's/^v//' ;;
    shfmt) gh api repos/mvdan/sh/releases/latest --jq .tag_name | sed 's/^v//' ;;
    actionlint) gh api repos/rhysd/actionlint/releases/latest --jq .tag_name | sed 's/^v//' ;;
    taplo) gh api repos/tamasfe/taplo/releases/latest --jq .tag_name | sed 's/^v//' ;;
  esac
}

# The artifact ci.yml downloads, and the name it looks up in
# tool-checksums.txt. Mirrors ci.yml; drifting from it is not silent --
# verify() there refuses to install a file it has no line for, so a name
# that stops matching fails the build rather than quietly skipping a check.
ci_url_of() {
  case "$1" in
    shellcheck) echo "https://github.com/koalaman/shellcheck/releases/download/v$2/shellcheck-v$2.linux.x86_64.tar.xz" ;;
    shfmt) echo "https://github.com/mvdan/sh/releases/download/v$2/shfmt_v${2}_linux_amd64" ;;
    actionlint) echo "https://github.com/rhysd/actionlint/releases/download/v$2/actionlint_${2}_linux_amd64.tar.gz" ;;
    taplo) echo "https://github.com/tamasfe/taplo/releases/download/$2/taplo-linux-x86_64.gz" ;;
  esac
}

# taplo's artifact name carries no version, unlike the other three -- upstream
# does not put one in it. A pin moved without a matching name change still
# updates the right line here, just at an unchanged filename.
ci_name_of() {
  case "$1" in
    shellcheck) echo "shellcheck-v$2.linux.x86_64.tar.xz" ;;
    shfmt) echo "shfmt_v${2}_linux_amd64" ;;
    actionlint) echo "actionlint_${2}_linux_amd64.tar.gz" ;;
    taplo) echo "taplo-linux-x86_64.gz" ;;
  esac
}

# The "Tools are the pinned versions" step in ci.yml asserts a literal
# version string, separate from the env var above -- a bump that moved only
# the env var would leave that assertion checking the old version forever,
# failing CI the moment the new binary actually installed.
ci_assertion_expr() { # ci_assertion_expr <tool> <have> <want>
  case "$1" in
    shellcheck) echo "s/version: $2\"/version: $3\"/" ;;
    shfmt) echo "s/= \"v$2\"/= \"v$3\"/" ;;
    actionlint) echo "s/head -1)\" = \"$2\"/head -1)\" = \"$3\"/" ;;
    taplo) echo "s/= \"taplo $2\"/= \"taplo $3\"/" ;;
  esac
}

ci_pinned_of() {
  awk -v k="$(ci_var_of "$1"):" '$1 == k { print $2; exit }' "$CI_WORKFLOW"
}

for tool in $CI_TOOLS; do
  have=$(ci_pinned_of "$tool")
  [ -n "$have" ] || {
    echo "$tool: no $(ci_var_of "$tool") in $CI_WORKFLOW" >&2
    exit 1
  }

  want=$(ci_latest_of "$tool")
  [ -n "$want" ] || {
    echo "$tool: could not resolve the latest version" >&2
    exit 1
  }

  if [ "$want" = "$have" ]; then
    printf '  %s%s%s %s is current\n' "$DIM" "$tool" "$OFF" "$have"
    continue
  fi

  newer_or_equal "$have" "$want" || {
    echo "$tool: latest is $want but $have is pinned; refusing to downgrade" >&2
    exit 1
  }

  url=$(ci_url_of "$tool" "$want")
  file="$tmp/$(ci_name_of "$tool" "$want")"
  # A published tag does not guarantee a published artifact. Fail here rather
  # than write a pin CI cannot install.
  curl -fsSL "$url" -o "$file" || {
    echo "$tool: $want is tagged but $url is not downloadable yet" >&2
    exit 1
  }
  hash=$(sha256sum "$file" | cut -d' ' -f1)

  old_name=$(ci_name_of "$tool" "$have")
  new_name=$(ci_name_of "$tool" "$want")
  # A substitution that matches nothing is not a no-op here, it is a pin
  # moved with no checksum to go with it. That does surface -- verify() in
  # ci.yml refuses a file it has no line for -- but as a failure in the pull
  # request rather than in the thing that caused it. Insist on the match
  # instead.
  awk -v old="$old_name" -v line="$hash  $new_name" \
    '$2 == old { print line; found = 1; next } { print } END { exit !found }' \
    "$CI_CHECKSUMS" > "$tmp/checksums" || {
    echo "$tool: $CI_CHECKSUMS has no line for $old_name, so the pin and the hashes already disagree" >&2
    exit 1
  }

  sed -e "s|^\([[:space:]]*$(ci_var_of "$tool"):[[:space:]]*\).*|\1$want|" \
    -e "$(ci_assertion_expr "$tool" "$have" "$want")" \
    "$CI_WORKFLOW" > "$tmp/workflow"

  # Every rewrite for this tool is staged and only then moved into place, so
  # failing partway cannot leave a bumped pin behind with a stale checksum or
  # assertion beside it.
  mv "$tmp/checksums" "$CI_CHECKSUMS"
  mv "$tmp/workflow" "$CI_WORKFLOW"

  # windows/configuration.winget pins the three of these it also runs on the
  # host (not actionlint, which the host never does) to the identical
  # version, in its own version field and in that resource's description.
  # Move it in the same pass or host and CI silently stop agreeing on what a
  # clean file looks like.
  case "$tool" in
    shellcheck | shfmt | taplo)
      awk -v id="      id: $tool" -v have="$have" -v want="$want" '
        /^    - resource:/ { in_block = 0 }
        $0 == id { in_block = 1 }
        in_block { gsub(have, want) }
        { print }
      ' "$HOST_MANIFEST" > "$tmp/manifest"
      mv "$tmp/manifest" "$HOST_MANIFEST"
      ;;
  esac

  printf '  %s%s%s %s -> %s%s%s\n' "$BOLD" "$tool" "$OFF" "$have" "$GREEN" "$want" "$OFF"
  changed=1
done

# ---------------------------------------------------------------------------
# mise pins
# ---------------------------------------------------------------------------

mise_repo_of() {
  case "$1" in
    gh) echo cli/cli ;;
    starship) echo starship/starship ;;
    eza) echo eza-community/eza ;;
    bat) echo sharkdp/bat ;;
    fd) echo sharkdp/fd ;;
    ripgrep) echo BurntSushi/ripgrep ;;
    fzf) echo junegunn/fzf ;;
    zoxide) echo ajeetdsouza/zoxide ;;
    jq) echo jqlang/jq ;;
    delta) echo dandavison/delta ;;
    uv) echo astral-sh/uv ;;
  esac
}

# Each project's tag form, the same as wsl/mise/config.toml's own header
# records them: jq tags as jq-1.8.2, ripgrep and delta publish bare numbers,
# everything else carries a leading v that mise expects stripped off.
mise_latest_of() {
  local tag
  tag=$(gh api "repos/$(mise_repo_of "$1")/releases/latest" --jq .tag_name) || return 1
  case "$1" in
    jq) echo "${tag#jq-}" ;;
    ripgrep | delta) echo "$tag" ;;
    *) echo "${tag#v}" ;;
  esac
}

mise_pinned_of() {
  awk -v t="^$1 = \"" '$0 ~ t { v = $0; sub(/^[a-z0-9_.-]+ = "/, "", v); sub(/".*/, "", v); print v; exit }' "$MISE_CONFIG"
}

for tool in $MISE_TOOLS; do
  have=$(mise_pinned_of "$tool")
  [ -n "$have" ] || {
    echo "$tool: no pin found in $MISE_CONFIG" >&2
    exit 1
  }

  want=$(mise_latest_of "$tool")
  [ -n "$want" ] || {
    echo "$tool: could not resolve the latest version" >&2
    exit 1
  }

  if [ "$want" = "$have" ]; then
    printf '  %s%s%s %s is current\n' "$DIM" "$tool" "$OFF" "$have"
    continue
  fi

  newer_or_equal "$have" "$want" || {
    echo "$tool: latest is $want but $have is pinned; refusing to downgrade" >&2
    exit 1
  }

  # Only the quoted version moves; whatever comment follows on the line
  # (most of these carry one) is carried through unchanged.
  sed -E "s|^($tool = \")[^\"]*(\".*)\$|\1$want\2|" "$MISE_CONFIG" > "$tmp/mise"
  mv "$tmp/mise" "$MISE_CONFIG"

  printf '  %s%s%s %s -> %s%s%s\n' "$BOLD" "$tool" "$OFF" "$have" "$GREEN" "$want" "$OFF"
  changed=1
done

if [ "$changed" -eq 0 ]; then
  printf '\nEverything is on its latest release.\n\n'
  exit 0
fi

printf '\nRun ./check.sh before committing: the CI tools on this machine will\n'
printf 'disagree with the new pins until they are upgraded to match. Run "mise\n'
printf 'install" to pick up any new mise pins.\n\n'
