FROM ubuntu:resolute AS base

# Make sure the builder and runner have the exact same versions
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

# Install build tools and dependencies
RUN apt-get update \
    && apt-get install -y git build-essential cmake wget xz-utils libssl-dev curl \
    libxcb-xinput0 libxcb-xinerama0 libxcb-cursor-dev libvulkan-dev glslc spirv-headers \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Llama.cpp cache invalidation, happens only when there is a new commit
ARG LLAMA_CPP_COMMIT=unknown

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git . \
    && echo "Building llama.cpp commit: $(git log -1 --format='%H')" \
    && cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_VULKAN=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    && cmake --build build --config Release -j $(nproc)

FROM base AS runner

# Runner cache invalidation, happens only when the cache version is incremented
ARG RUNNER_CACHE_VERSION
RUN if [ -n "$RUNNER_CACHE_VERSION" ]; then echo "Runner cache version: $RUNNER_CACHE_VERSION"; fi

RUN apt-get update \
    && apt-get install -y libgomp1 curl libvulkan1 mesa-vulkan-drivers \
    libglvnd0 libgl1 libglx0 libegl1 libgles2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
