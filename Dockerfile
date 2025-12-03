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

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/

RUN mkdir /models

EXPOSE 8080

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
