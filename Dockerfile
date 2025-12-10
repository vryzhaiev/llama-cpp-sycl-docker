ARG ONEAPI_VERSION=2025.3.2-0-devel-ubuntu24.04
ARG DEBIAN_FRONTEND=noninteractive

FROM intel/deep-learning-essentials:${ONEAPI_VERSION} AS builder

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git . \
    && cmake -B build \
    -DGGML_NATIVE=OFF \
    -DGGML_SYCL=ON \
    -DGGML_SYCL_F16=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx \
    && cmake --build build --config Release -j $(nproc)

FROM intel/deep-learning-essentials:${ONEAPI_VERSION}

# Update Level Zero and OpenCL to latest
RUN . /etc/os-release \
    && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0C0E6AF955CE463C03FC51574D098D70AFBE5E1F" \
    | gpg --dearmor -o /usr/share/keyrings/intel-graphics-archive-keyring-kobuk.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/intel-graphics-archive-keyring-kobuk.gpg] https://ppa.launchpadcontent.net/kobuk-team/intel-graphics/${ID} ${VERSION_CODENAME} main" \
    | tee /etc/apt/sources.list.d/intel-graphics.list \
    && apt-get update \
    && apt-get install --upgrade --no-install-recommends -y \
    libze1 \
    libze-dev \
    libze-intel-gpu1 \
    intel-opencl-icd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
