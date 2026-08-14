# Config overrides

Optional, per-branch `cassandra.yaml` tuning, applied on top of whatever
`conf/cassandra.yaml` the source ref ships by default.

## Convention

- One file per branch: `<ref_tag>.yaml`, where `ref_tag` is the SAME
  sanitized ref used for image tags elsewhere in this repo (tag-invalid
  characters replaced with `-`, capped at 128 chars — see
  `resolve-build-plan.sh`). For a plain branch name like
  `cassandra-5.0-rustyrazorblade`, `ref_tag` is the branch name unchanged, so
  the file is just `cassandra-5.0-rustyrazorblade.yaml`.
- No file for a given ref = no override. Every branch works fine with nothing
  here; this directory only ever adds tuning on top of upstream defaults.
- Only include the keys you want to change. Everything else in
  `cassandra.yaml` is left exactly as the source ref ships it.

## How it's applied

`build-cassandra-ref.yml` deep-merges the matching file (if any) onto
`conf/cassandra.yaml` in the checked-out Cassandra source, BEFORE
`ant artifacts` packages the tarball — see `merge-config-override.sh`. Both
build artifacts get the result from that single merge: the tarball directly,
and the GHCR image for free, since its `Dockerfile` just extracts the
tarball's `conf/` directory unchanged.

The merge (via `yq`'s `*` operator) recurses into nested maps — so overriding
one leaf of e.g. `memtable.configurations.default` doesn't clobber its
siblings — and replaces scalars/lists outright. Comments on any key you don't
touch survive the merge.

## Example

```yaml
# config-overrides/cassandra-5.0-rustyrazorblade.yaml
compaction_throughput: 128MiB/s

default_compaction:
  class_name: UnifiedCompactionStrategy
```
