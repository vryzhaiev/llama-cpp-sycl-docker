FROM ubuntu:noble AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    build-essential \
    cmake \
    git \
    curl \
    libcurl4-openssl-dev \
    gpg \
    ca-certificates \
    && curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor -o /usr/share/keyrings/oneapi.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi.gpg] https://apt.repos.intel.com/oneapi all main" \
    | tee /etc/apt/sources.list.d/oneapi.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    intel-oneapi-compiler-dpcpp-cpp \
    intel-oneapi-mkl-devel \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git . \
    && . /opt/intel/oneapi/setvars.sh \
    && cmake -B build \
    -DGGML_SYCL=ON \
    -DGGML_SYCL_F16=ON \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx \
    -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -j $(nproc)

FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    curl \
    gpg \
    ca-certificates \
    && curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor -o /usr/share/keyrings/oneapi.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi.gpg] https://apt.repos.intel.com/oneapi all main" \
    | tee /etc/apt/sources.list.d/oneapi.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    intel-oneapi-runtime-libs \
    libze1 \
    ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/drivers

# Use specific versions from the release doc (https://github.com/intel/compute-runtime/releases/tag/25.44.36015.5)
RUN curl -fsSLO https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-core-2_2.22.2+20121_amd64.deb \
    && curl -fsSLO https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-opencl-2_2.22.2+20121_amd64.deb \
    && curl -fsSLO https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-opencl-icd_25.44.36015.5-0_amd64.deb \
    && curl -fsSLO https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libigdgmm12_22.8.2_amd64.deb \
    && curl -fsSLO https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libze-intel-gpu1_25.44.36015.5-0_amd64.deb \
    && dpkg -i *.deb \
    && rm *.deb

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/
COPY entrypoint.sh /app/entrypoint.sh

RUN mkdir /models

ENV LD_LIBRARY_PATH="/app:/opt/intel/oneapi/redist/lib:/usr/lib/x86_64-linux-gnu"
ENV LC_ALL=C.utf8
ENV ZES_ENABLE_SYSMAN=1
ENV ONEAPI_DEVICE_SELECTOR=level_zero:0

EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["/app/llama-server", "--host", "0.0.0.0", "--port", "8080"]
