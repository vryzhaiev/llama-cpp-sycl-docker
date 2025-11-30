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
    -DGGML_NATIVE=OFF \
    -DGGML_SYCL=ON \
    -DGGML_SYCL_F16=ON \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx \
    -DGGML_BACKEND_DL=ON \
    && cmake --build build --config Release -j $(nproc)

FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive

RUN . /etc/os-release \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    curl \
    gpg \
    ca-certificates \
    && curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor -o /usr/share/keyrings/oneapi.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi.gpg] https://apt.repos.intel.com/oneapi all main" \
    | tee /etc/apt/sources.list.d/oneapi.list \
    && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0C0E6AF955CE463C03FC51574D098D70AFBE5E1F" \
    | gpg --dearmor -o /usr/share/keyrings/intel-graphics.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/intel-graphics.gpg] https://ppa.launchpadcontent.net/kobuk-team/intel-graphics/${ID} ${VERSION_CODENAME} main" \
    | tee /etc/apt/sources.list.d/intel-graphics.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    intel-oneapi-runtime-libs \
    intel-oneapi-umf \
    libze1 \
    ocl-icd-libopencl1 \
    libze-intel-gpu1 \
    intel-opencl-icd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/build/bin/* /app/
COPY entrypoint.sh /app/entrypoint.sh

RUN mkdir /models

ENV LD_LIBRARY_PATH="/app:/opt/intel/oneapi/redist/lib:/opt/intel/oneapi/umf/latest/lib:/usr/lib/x86_64-linux-gnu"
ENV LC_ALL=C.utf8
ENV ZES_ENABLE_SYSMAN=1
ENV ONEAPI_DEVICE_SELECTOR=level_zero:0

EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["/app/llama-server", "--host", "0.0.0.0", "--port", "8080"]
