ARG ONEAPI_VERSION=2026.0
ARG BASE_IMAGE_PATCH_VERSION=0
ARG UBUNTU_VERSION=24.04

FROM intel/deep-learning-essentials:${ONEAPI_VERSION}.${BASE_IMAGE_PATCH_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS base

ARG ONEAPI_VERSION

# Update Level Zero and OpenCL to latest, install dependencies
RUN apt-get update \
    && apt-get install --upgrade --no-install-recommends -y \
    libze1 \
    libze-dev \
    libze-intel-gpu1 \
    intel-opencl-icd \
    intel-ocloc \
    intel-oneapi-dnnl-devel-${ONEAPI_VERSION} \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

ARG ONEAPI_VERSION

# Node.js 20+ is required to build the web UI from source
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    libssl-dev \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Optional pinned commit. Empty (default) shallow-clones the latest master HEAD;
# a SHA triggers a full clone + checkout of that commit. Also acts as the cache key.
ARG LLAMA_CPP_COMMIT=

# FP16 support is disabled by default, can be enabled by passing GGML_SYCL_F16=ON build arg
ARG GGML_SYCL_F16=OFF

# Optional AOT target arch. When empty, the flag is omitted entirely (generic/JIT build).
# The list of supported architectures can be found in the table:
# https://github.com/intel/llvm/blob/sycl/sycl/doc/design/OffloadDesign.md#--offload-arch
ARG GGML_SYCL_DEVICE_ARCH=

# Build with SYCL Graph support (disabled at runtime by default, enable with GGML_SYCL_DISABLE_GRAPH=0)
RUN if [ -n "$LLAMA_CPP_COMMIT" ]; then \
    git clone https://github.com/ggml-org/llama.cpp.git . \
    && git checkout "$LLAMA_CPP_COMMIT"; \
    else \
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git .; \
    fi \
    && echo "Building llama.cpp commit: $(git log -1 --format='%H')" \
    && cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_SYCL=ON \
    -DGGML_SYCL_F16=${GGML_SYCL_F16} \
    ${GGML_SYCL_DEVICE_ARCH:+-DGGML_SYCL_DEVICE_ARCH=${GGML_SYCL_DEVICE_ARCH}} \
    -DGGML_SYCL_GRAPH=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx \
    -DCMAKE_PREFIX_PATH=/opt/intel/oneapi/dnnl/${ONEAPI_VERSION} \
    && cmake --build build --config Release -j $(nproc)

FROM base AS runner

ARG ONEAPI_VERSION

# Make libdnnl.so discoverable at runtime
ENV LD_LIBRARY_PATH=/opt/intel/oneapi/dnnl/${ONEAPI_VERSION}/lib:${LD_LIBRARY_PATH}

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
