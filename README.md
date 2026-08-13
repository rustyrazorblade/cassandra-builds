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
  with an immutable `sha-<short>` tag, a moving sanitized-ref tag, and (for
  matrix builds) a stable version-label tag (`5.0-HEAD`, `6.0-HEAD`, etc.).
  `latest` is never produced.
- **Per-build tarball release**: `apache-cassandra-<version>-<short-sha>-bin.tar.gz`,
  attached to a GitHub release tagged `cassandra-<version>-<short-sha>`. One
  release per build, additive, pruned manually.
- **Nightly release**: the matrix's aggregation job republishes every
  tracked branch's tarball under a stable name onto the single moving
  `nightly` release (deleted and recreated every run), giving URLs that never
  change:

  ```
  https://github.com/rustyrazorblade/cassandra-builds/releases/download/nightly/apache-cassandra-<version>-bin.tar.gz
  ```

## Consuming from easy-db-lab

Pin a tarball URL in `packer/cassandra/cassandra_versions.yaml`:

```yaml
- version: "my-branch"
  url: https://github.com/rustyrazorblade/cassandra-builds/releases/download/cassandra-<version>-<short-sha>/apache-cassandra-<version>-<short-sha>-bin.tar.gz
  java: "21"
  python: "3.11.9"
```

Or, for one of the nightly-tracked branches, use the stable `nightly` URL so
it always resolves to the latest build without editing the pin.

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
