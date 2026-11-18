# ZigQuery built from its tagged source, unmodified, so the binary is the code anyone can read at the pinned commit.
ARG ZIGQUERY_TAG=v0.0.7
ARG ZIGQUERY_COMMIT=62b47537ad4c8fade709e3198c2a72de62633ffb
ARG GOOGLESQL_COMMIT=1f8aa333f4d6353cd3a64471fc83121df72df3f7

FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8 AS toolchain
ARG TARGETARCH
ARG BAZELISK_VERSION=1.25.0
ARG BAZELISK_SHA256_AMD64=fd8fdff418a1758887520fa42da7e6ae39aefc788cf5e7f7bb8db6934d279fc4
ARG BAZELISK_SHA256_ARM64=4c8d966e40ac2c4efcc7f1a5a5cceef2c0a2f16b957e791fa7a867cce31e8fcb
ARG ZIG_VERSION=0.17.0
ARG ZIG_SHA256_AMD64=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026
ARG ZIG_SHA256_ARM64=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends ca-certificates curl git xz-utils unzip zip clang lld python3 build-essential \
 && useradd --create-home --uid 1500 builder && mkdir -p /work /tools && chown builder /work /tools
USER builder
WORKDIR /tools
RUN if [ "$TARGETARCH" = "arm64" ]; then BAZELISK_SHA256="$BAZELISK_SHA256_ARM64"; ZIG_SHA256="$ZIG_SHA256_ARM64"; ZIG_ARCH=aarch64; \
    else BAZELISK_SHA256="$BAZELISK_SHA256_AMD64"; ZIG_SHA256="$ZIG_SHA256_AMD64"; ZIG_ARCH=x86_64; fi \
 && mkdir -p bin zig \
 && curl -fsSL -o bin/bazel "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-${TARGETARCH}" \
 && echo "${BAZELISK_SHA256}  bin/bazel" | sha256sum --check \
 && chmod +x bin/bazel \
 && curl -fsSL -o zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" \
 && echo "${ZIG_SHA256}  zig.tar.xz" | sha256sum --check \
 && tar -xJf zig.tar.xz -C zig --strip-components=1 && rm zig.tar.xz
ENV PATH=/tools/bin:/tools/zig:$PATH CC=clang CXX=clang++

FROM toolchain AS build
ARG ZIGQUERY_TAG
ARG ZIGQUERY_COMMIT
ARG GOOGLESQL_COMMIT
# the SQL engine's largest files need several GB each to compile, so parallel jobs are sized to the builder's memory.
ARG BAZEL_JOBS=2
WORKDIR /work
RUN git clone --quiet --depth 1 --branch "$ZIGQUERY_TAG" https://github.com/Recidiviz/ZigQuery.git source \
 && cd source \
 && test "$(git rev-parse HEAD)" = "$ZIGQUERY_COMMIT" \
 && (git submodule update --init --depth 1 third_party/googlesql || git submodule update --init third_party/googlesql) \
 && test "$(git -C third_party/googlesql rev-parse HEAD)" = "$GOOGLESQL_COMMIT"
WORKDIR /work/source
# dependencies are fetched before the long compile, so an unreachable host fails the build in minutes.
RUN zig build --fetch
RUN bazel build -c opt --jobs="$BAZEL_JOBS" --local_resources=cpu="$BAZEL_JOBS" \
      //shim:libgooglesql_shim.so //shim:libgooglesql_shim_static_linux \
 && mkdir -p dist/shim \
 && cp -f bazel-bin/shim/libgooglesql_shim.so bazel-bin/shim/libgooglesql_shim_static_linux.o dist/shim/ \
 && chmod u+w dist/shim/* \
 && bazel shutdown
RUN zig build dist -Drelease=true -Dcpu=baseline \
      -Dshim-dylib=dist/shim/libgooglesql_shim.so \
      -Dshim-static-obj=dist/shim/libgooglesql_shim_static_linux.o \
      --prefix /work/stage \
 && mkdir -p /work/notices && cp LICENSE NOTICE THIRD_PARTY_NOTICES /work/notices/

FROM gcr.io/distroless/cc-debian13:nonroot@sha256:cb87acc574abe719b6e5c547384defa2f7b1f24af9605d3f618cf852495d8be2 AS base

FROM base
ARG ZIGQUERY_TAG
ARG ZIGQUERY_COMMIT
COPY --from=build /work/stage/bin/zigquery-server /usr/local/bin/zigquery-server
# the binary statically links the libraries these notices list, and their licenses require the notices to ship with it.
COPY --from=build /work/notices/ /usr/share/doc/zigquery/
# the base image has no shell, so its empty home folder is copied to make a data folder the non-root user owns.
COPY --from=base --chown=nonroot:nonroot /home/nonroot /data
LABEL org.opencontainers.image.description="ZigQuery ${ZIGQUERY_TAG} (Recidiviz/ZigQuery@${ZIGQUERY_COMMIT}) built from source, unmodified" \
      org.opencontainers.image.licenses="Apache-2.0"
EXPOSE 9050 9060
ENTRYPOINT ["/usr/local/bin/zigquery-server"]
