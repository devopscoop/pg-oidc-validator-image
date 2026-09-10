# pg-oidc-validator-image

Packages [Percona-Lab's pg_oidc_validator](https://github.com/Percona-Lab/pg_oidc_validator)
— an OAuth token validator for PostgreSQL 18's native OAuth (SASL
OAUTHBEARER) — as a [CloudNativePG image-volume extension image](https://cloudnative-pg.io/docs/devel/imagevolume_extensions),
published to `ghcr.io/devopscoop/pg-oidc-validator`.

Postgres ships no validator of its own, so this image is the missing piece
for the `pg-oauth` marker block in
[fluxcd-template](https://github.com/devopscoop/fluxcd-template)'s CNPG
database template (`apps/templates/cnpg-database/db-cluster.yaml`), which
wires psql logins through a Dex issuer. Consume it from a CNPG `Cluster`
like:

```yaml
spec:
  postgresql:
    extensions:
      - name: pg-oidc-validator
        image:
          reference: ghcr.io/devopscoop/pg-oidc-validator:18-trixie-YYYYMMDD
        # The image bundles libcurl and its dependency chain under system/,
        # because the postgres image ships no libcurl.
        ld_library_path:
          - system
    parameters:
      oauth_validator_libraries: "pg_oidc_validator"
```

## Image layout

- `lib/pg_oidc_validator.so` — the validator module; CNPG appends
  `<mount>/lib` to `dynamic_library_path` automatically. It is a validator
  library, not a `CREATE EXTENSION` extension, so there is no `share/`.
- `system/` — the `ldd` closure of the module (libcurl and friends), needed
  because the CloudNativePG postgres image does not ship libcurl. Requires
  `ld_library_path: ["system"]` on the consuming extension entry.
- `licenses/` — the upstream Apache-2.0 license.

## Tags

Every build pushes two tags:

- `<pg_major>-<distro>` (e.g. `18-trixie`) — moving, always the latest build.
- `<pg_major>-<distro>-<yyyymmdd>` — immutable. **Pin this one in gitops**:
  changing an extension image restarts the postgres pods, so it should be a
  reviewed git change, matching the exact-tag pinning used for `imageName`.

## Rebuild cadence and bumping

The workflow builds on push, weekly (the image vendors libcurl, so its
security fixes only ship via rebuilds), and on manual dispatch. To bump:

- **Validator**: upstream has no releases; update the `VALIDATOR_COMMIT` arg
  in the Dockerfile to a newer pinned commit.
- **Postgres major or distro**: update `PG_IMAGE` and `PG_MAJOR` in the
  Dockerfile and `PG_MAJOR`/`DISTRO` in the workflow together. The image is
  only compatible with the postgres major and distro it was built in.

## Requirements on the consuming side

- PostgreSQL 18+, CloudNativePG 1.27+ (image-volume extensions).
- Kubernetes 1.35+ (or 1.33/1.34 with the `ImageVolume` feature gate) and
  containerd 2.1+ / CRI-O 1.31+.
- Clients need psql 18 with libpq built against libcurl (Debian/Ubuntu PGDG
  ship it as `libpq-oauth`; Homebrew's builds lack it).
- With Dex as the issuer, use `scope=""` in the `pg_hba` oauth rule: Dex
  writes no scope claim into its tokens, and `scope=""` disables the
  validator's scope check (see the Dex section of the upstream README).
