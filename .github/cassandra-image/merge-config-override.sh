#!/usr/bin/env bash
#
# Pure, deterministic config-override merge for the build-cassandra-ref
# workflow. Deep-merges an optional per-branch YAML override onto the
# Cassandra source tree's conf/cassandra.yaml BEFORE `ant artifacts` packages
# it, so both build artifacts pick up the same tuned defaults from a single
# merge: the tarball directly, and the GHCR image for free (it just extracts
# the tarball's conf/ directory — see Dockerfile).
#
# Uses yq (mikefarah/yq, preinstalled on GitHub-hosted ubuntu runners): `*`
# deep-merges maps recursively (override wins on conflicts), replaces
# scalars/lists outright, and preserves comments on any key it doesn't touch
# — important since cassandra.yaml is a heavily documented reference file.
#
# Whether to call this at all (i.e. whether an override exists for the
# current ref) is the caller's job — overrides are optional per branch; see
# config-overrides/ and the build-cassandra-ref.yml workflow.

merge_config_override() {
  local override_file="$1" target_file="$2"

  if [[ -z "$override_file" || -z "$target_file" ]]; then
    echo "::error::merge_config_override requires <override_file> <target_file>" >&2
    return 1
  fi
  if [[ ! -f "$override_file" ]]; then
    echo "::error::override file not found: $override_file" >&2
    return 1
  fi
  if [[ ! -f "$target_file" ]]; then
    echo "::error::target file not found: $target_file" >&2
    return 1
  fi

  local merged
  merged="$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$target_file" "$override_file")" || {
    echo "::error::yq merge failed for ${override_file} -> ${target_file}" >&2
    return 1
  }
  printf '%s\n' "$merged" > "$target_file"
}
