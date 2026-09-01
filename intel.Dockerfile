ARG ONEAPI_VERSION=2026.1
ARG DNNL_VERSION=2026.0
ARG BASE_IMAGE_PATCH_VERSION=3
ARG UBUNTU_VERSION=26.04

FROM intel/deep-learning-essentials:${ONEAPI_VERSION}.${BASE_IMAGE_PATCH_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS base

ARG DNNL_VERSION

# Update the Level Zero / OpenCL driver stack to latest; install the offline compiler and oneDNN
RUN apt-get update \
    && apt-get install --upgrade --no-install-recommends -y \
    libze1 \
    libze-dev \
    libze-intel-gpu1 \
    intel-opencl-icd \
    intel-ocloc \
    intel-oneapi-dnnl-devel-${DNNL_VERSION} \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

ARG DNNL_VERSION
ARG NODE_VERSION="26"

# Node.js 20+ is required to build the web UI from source
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    libssl-dev \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Commit to build. Empty fetches the latest master HEAD.
# Also, busts the build layer's cache when it changes.
ARG LLAMA_CPP_COMMIT=

# FP16 is enabled by default; pass GGML_SYCL_F16=OFF to build FP32
ARG GGML_SYCL_F16=ON

# Optional AOT target arch. When empty, the flag is omitted entirely (generic/JIT build).
# The list of supported architectures can be found in the table:
# https://github.com/intel/llvm/blob/sycl/sycl/doc/design/OffloadDesign.md#--offload-arch
ARG GGML_SYCL_DEVICE_ARCH=

# Fetch, configure and build
RUN git init -q . \
    && git remote add origin https://github.com/ggml-org/llama.cpp.git \
    && git fetch --depth 1 origin "${LLAMA_CPP_COMMIT:-HEAD}" \
    && git checkout -q FETCH_HEAD \
    && echo "Building llama.cpp commit: $(git log -1 --format='%H')" \
    && cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_SYCL=ON \
    -DGGML_SYCL_F16=${GGML_SYCL_F16} \
    ${GGML_SYCL_DEVICE_ARCH:+-DGGML_SYCL_DEVICE_ARCH=${GGML_SYCL_DEVICE_ARCH}} \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_UI=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx \
    -DCMAKE_PREFIX_PATH=/opt/intel/oneapi/dnnl/${DNNL_VERSION} \
    && cmake --build build --config Release -j $(nproc)

FROM base AS runner

ARG DNNL_VERSION

# Make libdnnl.so discoverable at runtime
ENV LD_LIBRARY_PATH=/opt/intel/oneapi/dnnl/${DNNL_VERSION}/lib:${LD_LIBRARY_PATH}

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
