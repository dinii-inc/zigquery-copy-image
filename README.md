# ZigQuery image built from source

A container image of [ZigQuery](https://github.com/Recidiviz/ZigQuery), a BigQuery emulator by Recidiviz, compiled here from its tagged source without changes.

## Why this exists

The upstream project publishes its own image, but that image carries no build provenance, so it cannot be tied to a source commit. This repository builds the same server from a pinned commit in the open, so the binary can be traced to code anyone can read.

## What the build does

- Fetches ZigQuery at the tag in the `Dockerfile` and stops unless the checked-out commit, and the commit of its GoogleSQL submodule, equal the pinned hashes.
- Downloads the build tools (Bazelisk, Zig) and verifies their checksums.
- Compiles the server exactly as the upstream release does and copies it into a distroless base image, together with upstream's `LICENSE`, `NOTICE` and `THIRD_PARTY_NOTICES`.
- Publishes `linux/amd64` and `linux/arm64` with an SBOM and build provenance attached.

Nothing is patched and nothing is added to the server.

## Use

```sh
docker run --rm -p 9050:9050 ghcr.io/dinii-inc/zigquery-copy-image:v0.0.7 --project=my-project
```

Arguments are passed to `zigquery-server`; see the upstream documentation.

## Updating to a new ZigQuery version

Change `ZIGQUERY_TAG`, `ZIGQUERY_COMMIT` and `GOOGLESQL_COMMIT` in the `Dockerfile` and merge. The workflow rebuilds and publishes the new tag.

## License

ZigQuery is licensed under Apache-2.0 by its authors; the image ships their license and notices under `/usr/share/doc/zigquery/`. The build files in this repository are licensed under Apache-2.0 as well.
