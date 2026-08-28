# cassandra-builds

CI-built Apache Cassandra artifacts — GHCR container images and binary
tarballs — for arbitrary branches, tags, or commit SHAs, including forks.

## Why this repo exists

This started as a workflow inside [easy-db-lab](https://github.com/rustyrazorblade/easy-db-lab).
Every build published a per-build GitHub release (`cassandra-<version>-<sha>`),
which meant every nightly build of every tracked branch left a permanent git
tag on easy-db-lab — a repo that has nothing to do with Cassandra versioning.
This repo exists specifically to host that: build artifacts and their tags
belong on a repo whose entire purpose is building Cassandra, not on a
consumer's repo.

## What gets built

Two workflows:

- **`build-cassandra-ref.yml`** — on-demand build of a single arbitrary ref.
  Trigger it manually (Actions tab, or `gh workflow run`) for any branch, tag,
  or SHA, including forks via the `repo` input.
- **`build-cassandra-set.yml`** — nightly (2am UTC) build of the tracked set
  below, via `build-cassandra-ref.yml` as a reusable workflow. Also
  republishes every tarball to a moving `nightly` release with stable,
  never-changing download URLs.

### Currently tracked branches (nightly matrix)

| Label | Repo | Ref |
| --- | --- | --- |
| `5.0-HEAD` | `apache/cassandra` | `cassandra-5.0` |
| `6.0-HEAD` | `apache/cassandra` | `cassandra-6.0` |
| `trunk` | `apache/cassandra` | `trunk` |
| `6.0-rustyrazorblade-HEAD` | `rustyrazorblade/cassandra` | `cassandra-6.0-rustyrazorblade` |
| `5.0-rustyrazorblade-HEAD` | `rustyrazorblade/cassandra` | `cassandra-5.0-rustyrazorblade` |

## Adding a new branch to the nightly matrix

Add one entry to the `matrix.include` list in
[`.github/workflows/build-cassandra-set.yml`](.github/workflows/build-cassandra-set.yml):

```yaml
- repo: owner/cassandra        # defaults to apache/cassandra if omitted
  ref: your-branch-name
  version: "your-branch-name-HEAD"   # MUST be quoted — see the comment above the matrix
```

Also add the new stable URL to the `publish-nightly` job's release body (for
documentation) — not required for the mechanism to work, just for
discoverability.

That's it — the next scheduled (or manually triggered) run picks it up. No
other files need to change.

## Config overrides (optional)

Drop a `<ref_tag>.yaml` file in [`config-overrides/`](config-overrides/) to
tune `cassandra.yaml` defaults for a specific branch — e.g.
`config-overrides/cassandra-5.0-rustyrazorblade.yaml`. It's deep-merged onto
the branch's default `conf/cassandra.yaml` before packaging, so both the
tarball and the GHCR image (which just extracts the tarball's `conf/`) pick up
the same tuned defaults. No file for a ref = no override, everything else
about that branch's default config is untouched. See
[`config-overrides/README.md`](config-overrides/README.md) for the merge
mechanics.

## Triggering a one-off build for any ref

You don't need to touch the matrix for a single build — run the reusable
workflow directly:

```bash
gh workflow run build-cassandra-ref.yml \
  -f ref=my-branch-name \
  -f repo=someone/cassandra
```

Leave `repo` unset to build from `apache/cassandra`. `jdk` and `base_image`
inputs override the auto-mapped build JDK / runtime JRE base image if a
branch needs something different than its version normally maps to.

## Where artifacts land

- **GHCR image**: `ghcr.io/rustyrazorblade/cassandra-builds/cassandra`, tagged
  with a moving sanitized-ref tag and (for matrix builds) a stable
  version-label tag (`5.0-HEAD`, `6.0-HEAD`, etc.). The build also applies an
  immutable `sha-<short>` tag locally, so the smoke test has a concrete image
  to run, but that tag is never pushed. `latest` is never produced.
- **Per-ref tarball release**: `apache-cassandra-<version>-<short-sha>-bin.tar.gz`,
  attached to a GitHub release tagged after the ref itself (e.g.
  `cassandra-6.0-rustyrazorblade`). One release per ref, deleted and recreated
  on every run, so builds never accumulate tags.

  The release tag is stable, but the asset filename still embeds the short
  SHA. The full download URL therefore changes on every build. Do not pin it.
  Pin a `nightly` URL instead.
- **Nightly release**: the matrix's aggregation job republishes every
  tracked branch's tarball under a stable name onto the single moving
  `nightly` release (deleted and recreated every run), giving URLs that never
  change:

  ```
  https://github.com/rustyrazorblade/cassandra-builds/releases/download/nightly/apache-cassandra-<version>-bin.tar.gz
  ```

## Consuming from easy-db-lab

For a nightly-tracked branch, pin the stable `nightly` URL in
`packer/cassandra/cassandra_versions.yaml`. It always resolves to the latest
build, and you never edit the pin:

```yaml
- version: "5.0-HEAD"
  url: https://github.com/rustyrazorblade/cassandra-builds/releases/download/nightly/apache-cassandra-5.0-HEAD-bin.tar.gz
  java: "17"
  python: "3.11.9"
```

For an untracked ref, take the URL from the run summary of the build you want.
That URL is good only until the next build of the same ref, which deletes the
release and attaches a tarball under a new filename. To pin a ref for longer,
add it to the nightly matrix.

## Image assembly

The image is assembled from repo-owned files in `.github/cassandra-image/`:

- `Dockerfile` — reproduces the Docker Official `cassandra` image layout
  (`CASSANDRA_HOME=/opt/cassandra`, `/var/lib/cassandra` volume, exposed
  ports, gosu step-down, jemalloc) but injects the tarball this workflow just
  built instead of downloading + GPG-verifying a released one.
- `docker-entrypoint.sh` — a byte-identical vendored copy of the upstream
  entrypoint. Re-vendor deliberately if upstream changes; never hand-edit.
- `resolve-build-plan.sh` / `resolve-ref.sh` — pure, sourceable shell
  functions for the version → JDK / ant-flags / base-image / tag mapping and
  ref resolution. Unit-tested by their `*.test.sh` siblings, run directly via
  `bash` (see `.github/workflows/test.yml`) — no build system required.

## Testing locally

```bash
bash .github/cassandra-image/resolve-build-plan.test.sh
bash .github/cassandra-image/resolve-ref.test.sh
```

Both are pure — no network, no Docker.
