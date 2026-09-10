# Packages Percona-Lab's pg_oidc_validator as a CloudNativePG image-volume
# extension image (https://cloudnative-pg.io/docs/devel/imagevolume_extensions):
#   lib/       the validator module (appended to dynamic_library_path by CNPG)
#   system/    the libcurl dependency closure — the postgres image ships no
#              libcurl, so the consuming Cluster must list "system" under the
#              extension's ld_library_path
#   licenses/  the upstream Apache-2.0 license
#
# Build args pin everything; bump them deliberately. PG_IMAGE and PG_MAJOR
# must move together, and the image only works against the same postgres
# major and distro it was built in.
ARG PG_IMAGE=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie

# Build inside the exact server image so the ABI always matches.
FROM $PG_IMAGE AS builder
ARG PG_MAJOR=18
# Upstream publishes no releases, only a rolling main — pin a commit.
ARG VALIDATOR_COMMIT=ba9c4cb2dc9bd2e9779c7a33f7a30c9bb8c97862
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential "postgresql-server-dev-${PG_MAJOR}" \
      libcurl4-openssl-dev git ca-certificates
RUN git clone --recurse-submodules \
      https://github.com/Percona-Lab/pg_oidc_validator /src \
 && git -C /src checkout "${VALIDATOR_COMMIT}" \
 && git -C /src submodule update --init --recursive \
 && make -C /src USE_PGXS=1 -j"$(nproc)"
# The ldd closure over-copies libraries the postgres image already has —
# harmless, they are the same distro builds and merely shadow themselves.
RUN mkdir -p /out/lib /out/system /out/licenses/pg_oidc_validator \
 && cp /src/pg_oidc_validator.so /out/lib/ \
 && cp /src/LICENSE.txt /out/licenses/pg_oidc_validator/ \
 && for lib in $(ldd /src/pg_oidc_validator.so \
                 | awk '/=> \//{print $3}' \
                 | grep -vE 'libc\.so|ld-linux'); do \
      cp -Ln "$lib" /out/system/; \
    done

FROM scratch
COPY --from=builder /out/ /
