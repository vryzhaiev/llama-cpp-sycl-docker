# llama.cpp-docker

Configurable Docker builds for the [llama.cpp](https://github.com/ggml-org/llama.cpp) server
(`llama-server`) with GPU acceleration (currently, only SYCL and Vulkan backends). The
**Dockerfiles** are configurable by GPU backend, FP16, ahead-of-time compilation for a specific
architecture, or a specific upstream commit. Prebuilt, ready-to-run images are published to GHCR
for convenience.

llama.cpp publishes official images of its own, but they have mostly fixed build options,
dependencies that are refreshed less often, and a lag behind `master` — a just-pushed commit can
take hours to appear in a release. Building from these Dockerfiles lets you select your own options
and target the exact commit you need, without the wait.

These builds are **primarily focused on Intel GPUs** (SYCL), with a Vulkan build for other and
mixed hardware. The Vulkan backend can be *faster* than SYCL on some hardware — or at particular
points in llama.cpp's development, as each backend is optimized independently — so it is worth
benchmarking both, even on Intel.

Images: **`ghcr.io/vryzhaiev/llama.cpp`**

## Available images

| Tag | Backend | Best for |
|---|---|---|
| `latest-intel` | Intel GPU (SYCL) | Any Intel GPU |
| `latest-intel-fp16` | Intel GPU (SYCL) | Any Intel GPU, FP16-capable — usually faster |
| `latest-intel-arl-fp16` | Intel GPU (SYCL) | **Arrow Lake-H** iGPUs, tuned specifically for that hardware |
| `latest-vulkan` | Vulkan | Non-Intel or mixed GPUs (AMD, NVIDIA, …) |

Not sure? Start with **`latest-intel-fp16`** on an Intel GPU, or **`latest-vulkan`** elsewhere.
The `arl-fp16` image is compiled ahead-of-time for Arrow Lake-H — prefer the generic `intel`
tags on other Intel GPUs.

## Quick start

### Intel GPU (SYCL)

```sh
docker run --rm -it \
  --device /dev/dri:/dev/dri \
  -v /path/to/models:/models \
  -p 8080:8080 \
  ghcr.io/vryzhaiev/llama.cpp:latest-intel-fp16 \
  -m /models/your-model.gguf -ngl 99 --host 0.0.0.0 --port 8080
```

### Vulkan

```sh
docker run --rm -it \
  --device /dev/dri:/dev/dri \
  -v /path/to/models:/models \
  -p 8080:8080 \
  ghcr.io/vryzhaiev/llama.cpp:latest-vulkan \
  -m /models/your-model.gguf -ngl 99 --host 0.0.0.0 --port 8080
```

### Docker Compose example

```yaml
services:
  llama:
    image: ghcr.io/vryzhaiev/llama.cpp:latest-intel-fp16
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - ./models:/models
    ports:
      - "8080:8080"
    command: >-
      -m /models/your-model.gguf -ngl 99 --host 0.0.0.0 --port 8080
```

Then open <http://localhost:8080> for the web UI, or use the API:

```sh
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

> **GPU access:** pass your render device with `--device /dev/dri:/dev/dri`.

## Intel GPU driver (`i915` vs `xe`)

Intel GPUs use one of two kernel drivers. **`i915`** is the legacy driver and supports all Intel
GPUs. **`xe`** is the newer driver, recommended on recent architectures (Lunar Lake, Battlemage,
and newer); it can also be enabled on some earlier Xe/Arc parts. Older GPUs are `i915`-only.

Check which driver is bound:

```sh
lspci -k -nn | grep -iEA3 'vga|display'
```

If your GPU supports `xe` but is bound to `i915`, you can switch it on **Ubuntu 24.04+**
(kernel 6.8+):

1. Note the PCI device ID — the `XXXX` in the `8086:XXXX` value from the command above.
2. In `/etc/default/grub`, append to `GRUB_CMDLINE_LINUX_DEFAULT`:
   `i915.force_probe=!XXXX xe.force_probe=XXXX`
3. Apply and reboot: `sudo update-grub && sudo reboot`
4. Re-run the `lspci` command and confirm it now shows `Kernel driver in use: xe`.

## Configuration

- **Everything after the image name is passed straight to `llama-server`** — so any
  [server flag](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#usage)
  works (`-m`, `-ngl`/`--n-gpu-layers`, `-c`, `--host`, `--port`, `--chat-template`, …).
- **Models:** mount a directory to `/models` and reference files under it with `-m`.
- **Port:** the server listens on **8080**; pass `--host 0.0.0.0` so it's reachable through the
  published port.

### Intel runtime tuning (optional)

Set these as container environment variables (`-e VAR=value`). Defaults are sensible — these are
for tuning or troubleshooting.

| Env var | Default | Effect |
|---|---|---|
| `ONEAPI_DEVICE_SELECTOR` | auto | Pick the device/backend, e.g. `level_zero:0` for the first Level Zero GPU |
| `GGML_SYCL_ENABLE_DNN` | `1` | Set `0` to disable the oneDNN matmul path (enabled by default; its performance impact varies by hardware and workload) |
| `GGML_SYCL_ENABLE_FLASH_ATTN` | `1` | Set `0` to disable Flash Attention |
| `GGML_SYCL_ENABLE_OPT` | `1` | Set `0` to disable Intel GPU optimizations (troubleshooting; also recommended for Intel GPUs older than Gen 10) |
| `ZES_ENABLE_SYSMAN` | `0` | Set `1` to let the server report free GPU memory |
| `GGML_SYCL_ENABLE_GRAPH` | `0` | Set `1` to enable SYCL Graph — though it likely gives no benefit yet |
| `GGML_SYCL_DEBUG` | `0` | Set `1` for verbose SYCL logging (troubleshooting) |

See the [SYCL backend docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/SYCL.md#environment-variable)
for the complete list.

## Building locally

You can build any variant directly from the Dockerfiles rather than pulling a published image:

```sh
docker build -f intel.Dockerfile -t llama.cpp:intel .    # generic Intel (SYCL)
docker build -f vulkan.Dockerfile -t llama.cpp:vulkan .  # Vulkan
```

Build options are passed with `--build-arg` — for example `GGML_SYCL_F16=ON` to enable FP16.

> **Freshness:** a local build fetches `master` HEAD on the first run, then reuses the cached clone
> on rebuilds — so it won't pick up new upstream commits on its own. Use `--no-cache` to rebuild
> against the latest HEAD; alternatively, pass `--build-arg LLAMA_CPP_COMMIT=<sha>` to build a
> specific commit. The published images avoid this: CI resolves the current HEAD and passes it on
> every build.

### Building for a specific Intel GPU (AOT)

The `latest-intel-arl-fp16` image is compiled ahead-of-time (AOT) for Arrow Lake-H, which skips
runtime kernel compilation and can improve performance on that hardware. To build an image tuned
for a different Intel architecture, pass `GGML_SYCL_DEVICE_ARCH` (usually together with FP16):

```sh
docker build -f intel.Dockerfile \
  --build-arg GGML_SYCL_F16=ON \
  --build-arg GGML_SYCL_DEVICE_ARCH=arl_h \
  -t llama.cpp:intel-aot .
```

Set `GGML_SYCL_DEVICE_ARCH` to your GPU's offload target — see Intel's
[offload architecture table](https://github.com/intel/llvm/blob/sycl/sycl/doc/design/OffloadDesign.md#--offload-arch)
for the available names. AOT builds take noticeably longer to compile and are specialized for the
chosen architecture; omit the arg for a generic build that runs on any Intel GPU.

## Updates

Images track the latest llama.cpp `master` and are rebuilt automatically (including a weekly
refresh of the GPU drivers). Specific commits can also be published as `<short-sha>-intel…` tags
when a reproducible pin is needed.

## License

The images bundle llama.cpp, which is [MIT licensed](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE).
Intel oneAPI runtime components in the Intel images are subject to Intel's own license terms.
