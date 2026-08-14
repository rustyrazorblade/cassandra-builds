#!/usr/bin/env bash
#
# Unit tests for merge-config-override.sh — the pure deep-merge logic the
# build-cassandra-ref workflow uses to apply an optional per-branch config
# override onto conf/cassandra.yaml before packaging.
#
# Pure: no network (yq is a local static binary), no Docker.
#
# Run directly:  ./merge-config-override.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/cassandra-image/merge-config-override.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/merge-config-override.sh"

tests_run=0
tests_failed=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  tests_run=$((tests_run + 1))
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   - ${desc}"
  else
    echo "FAIL - ${desc}: expected [${expected}], got [${actual}]"
    tests_failed=$((tests_failed + 1))
  fi
}

assert_fails_merge() {
  local desc="$1" override="$2" target="$3"
  tests_run=$((tests_run + 1))
  if merge_config_override "$override" "$target" >/dev/null 2>&1; then
    echo "FAIL - ${desc}: expected non-zero exit, got success"
    tests_failed=$((tests_failed + 1))
  else
    echo "ok   - ${desc} (failed as expected)"
  fi
}

# --- flat scalar override replaces a key, unrelated keys untouched ----------
target="${TMP_DIR}/flat-target.yaml"
cat > "$target" <<'EOF'
compaction_throughput: 64MiB/s
endpoint_snitch: SimpleSnitch
EOF
override="${TMP_DIR}/flat-override.yaml"
cat > "$override" <<'EOF'
compaction_throughput: 128MiB/s
EOF
merge_config_override "$override" "$target"
assert_eq "flat scalar override replaces the key" "128MiB/s" \
  "$(yq '.compaction_throughput' "$target")"
assert_eq "unrelated flat key is untouched" "SimpleSnitch" \
  "$(yq '.endpoint_snitch' "$target")"

# --- nested dict merge: overriding one nested leaf preserves its siblings ---
target="${TMP_DIR}/nested-target.yaml"
cat > "$target" <<'EOF'
memtable:
  configurations:
    skiplist:
      class_name: SkipListMemtable
    trie:
      class_name: TrieMemtable
    default:
      inherits: skiplist
EOF
override="${TMP_DIR}/nested-override.yaml"
cat > "$override" <<'EOF'
memtable:
  configurations:
    default:
      inherits: trie
EOF
merge_config_override "$override" "$target"
assert_eq "nested override changes the targeted leaf" "trie" \
  "$(yq '.memtable.configurations.default.inherits' "$target")"
assert_eq "sibling nested key (skiplist definition) survives the merge" "SkipListMemtable" \
  "$(yq '.memtable.configurations.skiplist.class_name' "$target")"
assert_eq "sibling nested key (trie definition) survives the merge" "TrieMemtable" \
  "$(yq '.memtable.configurations.trie.class_name' "$target")"

# --- override can introduce a brand-new top-level key (e.g. a commented-out
#     upstream default like default_compaction) -----------------------------
target="${TMP_DIR}/newkey-target.yaml"
cat > "$target" <<'EOF'
compaction_throughput: 64MiB/s
EOF
override="${TMP_DIR}/newkey-override.yaml"
cat > "$override" <<'EOF'
default_compaction:
  class_name: UnifiedCompactionStrategy
EOF
merge_config_override "$override" "$target"
assert_eq "override can add a new top-level key" "UnifiedCompactionStrategy" \
  "$(yq '.default_compaction.class_name' "$target")"

# --- a comment on an untouched key survives the merge -----------------------
target="${TMP_DIR}/comment-target.yaml"
cat > "$target" <<'EOF'
# how big your writes can get before we complain
compaction_throughput: 64MiB/s # tune me
endpoint_snitch: SimpleSnitch
EOF
override="${TMP_DIR}/comment-override.yaml"
cat > "$override" <<'EOF'
compaction_throughput: 128MiB/s
EOF
merge_config_override "$override" "$target"
tests_run=$((tests_run + 1))
if grep -q "how big your writes can get" "$target" && grep -q "# tune me" "$target"; then
  echo "ok   - comments on the overridden key's line/surroundings survive the merge"
else
  echo "FAIL - comments were dropped by the merge"
  tests_failed=$((tests_failed + 1))
fi

# --- missing override file fails fast ---------------------------------------
assert_fails_merge "missing override file fails fast" \
  "${TMP_DIR}/does-not-exist.yaml" "$target"

# --- missing target file fails fast -----------------------------------------
override="${TMP_DIR}/only-override.yaml"
cat > "$override" <<'EOF'
a: 1
EOF
assert_fails_merge "missing target file fails fast" \
  "$override" "${TMP_DIR}/does-not-exist-target.yaml"

echo ""
echo "${tests_run} tests, ${tests_failed} failed"
[[ "$tests_failed" -eq 0 ]]
