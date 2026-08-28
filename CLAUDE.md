# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo builds Apache Cassandra from arbitrary git refs and publishes two artifacts: a GHCR container image and a binary tarball on a GitHub release.  It exists so that the build tags land on a repo dedicated to Cassandra artifacts, not on a consumer repo such as `easy-db-lab`.

There is no application code and no build system.  The repo is GitHub Actions YAML plus pure, sourceable bash functions.  Read `README.md` and `config-overrides/README.md` for the operator-facing view.

## Commands

Run the unit tests directly.  All three are pure: no network, no Docker.

```bash
bash .github/cassandra-image/resolve-build-plan.test.sh
bash .github/cassandra-image/resolve-ref.test.sh
bash .github/cassandra-image/merge-config-override.test.sh
```

The test harness is hand-rolled.  There is no test runner and no way to select a single case from the command line.  To run one case, comment out the other `assert_*` calls, or source the script and call the function directly:

```bash
source .github/cassandra-image/resolve-build-plan.sh
VERSION=5.0.3 SHORT_SHA=abc123def456 SOURCE_REF=cassandra-5.0 \
  JDK_OVERRIDE= BASE_IMAGE_OVERRIDE= REPO_OWNER=o REPO_NAME=r compute_build_plan
```

`merge-config-override.test.sh` needs `yq` (mikefarah/yq) on the PATH.

Trigger a one-off build for any ref:

```bash
gh workflow run build-cassandra-ref.yml -f ref=my-branch -f repo=someone/cassandra
```

Note: `resolve-build-plan.test.sh` names `./gradlew testCassandraBuildPlan` in its header.  That command is stale; this repo has no Gradle wrapper.

## Architecture

### The pure-shell extraction

The workflow "thinking" lives in sourceable bash functions under `.github/cassandra-image/`, not in the YAML.  Each has a `*.test.sh` sibling.  The workflow sources the file, calls the function, and appends its `key=value` stdout to `$GITHUB_OUTPUT`.

- `resolve-ref.sh` — `resolve_ref` turns a branch, tag, or SHA into an immutable SHA.  The network call is injected through `LS_REMOTE_CMD` so tests can stub it.
- `resolve-build-plan.sh` — `compute_build_plan` maps a version plus a ref into the whole build plan: build JDK, ant flags, base image, image repo, tags, tarball name, release tag.
- `merge-config-override.sh` — `merge_config_override` deep-merges a per-branch YAML override onto `conf/cassandra.yaml`.

Put new decision logic in one of these functions with a test.  Do not add it inline to the YAML.

### The two workflows

`build-cassandra-ref.yml` builds one ref.  It runs on `workflow_dispatch` and on `workflow_call`.  It has three sequential jobs, which makes "build fails, nothing publishes" structural:

1. `resolve` — resolve the ref, read `base.version` from `build.xml`, compute the build plan.
2. `build` — apply the optional config override, run `ant artifacts`, rename and upload the tarball.
3. `publish` — build the image locally, smoke-test it, push to GHCR, then delete and recreate the release.

`build-cassandra-set.yml` is the nightly caller.  It runs `build-cassandra-ref.yml` once per matrix entry, then aggregates every tarball onto the single moving `nightly` release under stable filenames.  To track a new branch, add one entry to `matrix.include`.  No other file needs to change.

### Publishing model

Every release in this repo is moving, not additive.  Both workflows delete the release and its tag, then recreate it.  A per-ref build owns exactly one release, named after the sanitized ref.  The nightly job owns the `nightly` release.  The result is one permanent download URL per branch.

The image gets a moving `:<ref_tag>` tag, and a stable version tag such as `:5.0-HEAD` when a matrix caller passes `stable_version`.

### The container image

`.github/cassandra-image/Dockerfile` reproduces the Docker Official `cassandra` image layout, but injects the tarball this repo just built instead of downloading and verifying a release.  The image picks up any config override for free, because it extracts the tarball's `conf/` directory unchanged.

`docker-entrypoint.sh` is a byte-identical vendored copy of the upstream file.  Never hand-edit it.  Re-vendor it deliberately if upstream changes.

## Invariants

- **Never produce the `latest` tag.**  `compute_build_plan` fails if the sanitized ref would yield it.
- **Keep base images pinned to a specific Ubuntu LTS variant.**  A floating `-jre` tag drifts to a Python version outside the range that `cqlsh` supports, which breaks `cqlsh`.  See the comments in `resolve-build-plan.sh` for the range per Cassandra major.
- **Quote every `version` in the nightly matrix.**  A bare `6.0` is a YAML float, and GitHub Actions stringifies it to `6`.
- **`sha_tag` is local only.**  It exists so the smoke test has a concrete image.  It is never pushed.
- **The tag sanitizer is `sed 's/[^a-zA-Z0-9._-]/-/g' | cut -c1-128`.**  It appears in `resolve-build-plan.sh` and inline in three places in `build-cassandra-ref.yml`.  If you change one, change all of them.
- **The publish job must smoke-test before it pushes.**  The test starts the image on a pinned IP and queries `system.local` over CQL.  Do not weaken it to a `nodetool` check alone.
- **A config override file is named `<ref_tag>.yaml`.**  The `ref_tag` is the same sanitized ref used for image tags.
