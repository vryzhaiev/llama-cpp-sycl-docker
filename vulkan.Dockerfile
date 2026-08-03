FROM ubuntu:resolute AS base

# Make sure the builder and runner have the exact same versions
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

ARG NODE_VERSION="26"

# Install build tools and dependencies. Node.js 20+ is required to build the web UI from source.
RUN apt-get update \
    && apt-get install --no-install-recommends -y curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    git build-essential cmake wget xz-utils nodejs libssl-dev \
    libxcb-xinput0 libxcb-xinerama0 libxcb-cursor-dev libvulkan-dev glslc spirv-headers \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Commit to build. Empty fetches the latest master HEAD.
# Also, busts the build layer's cache when it changes.
ARG LLAMA_CPP_COMMIT=

# Fetch, configure and build
RUN git init -q . \
    && git remote add origin https://github.com/ggml-org/llama.cpp.git \
    && git fetch --depth 1 origin "${LLAMA_CPP_COMMIT:-HEAD}" \
    && git checkout -q FETCH_HEAD \
    && echo "Building llama.cpp commit: $(git log -1 --format='%H')" \
    && cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_VULKAN=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    && cmake --build build --config Release -j $(nproc)

FROM base AS runner

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    libgomp1 curl ca-certificates libvulkan1 mesa-vulkan-drivers \
    libglvnd0 libgl1 libglx0 libegl1 libgles2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
