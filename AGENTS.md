# AGENTS.md

Guidance for AI agents and developers working on this repository.

## What this repo is

Configurable Dockerfiles that build the [llama.cpp](https://github.com/ggml-org/llama.cpp)
server (`llama-server`) for Intel GPUs (SYCL) and cross-vendor Vulkan. The Dockerfiles are the
primary artifact; the CI workflows also publish prebuilt images to `ghcr.io/vryzhaiev/llama.cpp`
as a convenience. There is no application source here — each build clones llama.cpp at build time
and compiles it.

## Repository layout

| Path | Purpose |
|---|---|
| `intel.Dockerfile` | Intel oneAPI / SYCL build (the actively-developed one) |
| `vulkan.Dockerfile` | Vulkan build — same clone/UI/pinning patterns as Intel; no oneDNN, AOT, or variants |
| `.github/workflows/build-intel.yml` | CI for the Intel images |
| `.github/workflows/build-vulkan.yml` | CI for the Vulkan image |

`docker-compose.yaml` is git-ignored (local dev convenience), so don't rely on it existing.

## Image variants / tags

Published tags on `ghcr.io/vryzhaiev/llama.cpp`:

| Tag | Backend | FP16 | AOT arch | Notes |
|---|---|---|---|---|
| `latest-intel` | SYCL | off | — | Generic Intel GPU (JIT) |
| `latest-intel-fp16` | SYCL | on | — | Generic Intel GPU, FP16 |
| `latest-intel-arl-fp16` | SYCL | on | `arl_h` | AOT-compiled for Arrow Lake-H iGPUs |
| `latest-vulkan` | Vulkan | — | — | Cross-vendor |

Manually-dispatched **pinned** builds replace the `latest-` prefix with the 7-char commit SHA:
`<short7-sha>-intel[-fp16|-arl-fp16]` and `<short7-sha>-vulkan`.

## Intel Dockerfile architecture

Three stages, and the split matters:

- **`base`** — `FROM intel/deep-learning-essentials:<oneapi>-devel-ubuntu<ver>`, then a
  single `apt --upgrade` install of the GPU runtime (Level Zero, OpenCL, `intel-ocloc`)
  **and** `intel-oneapi-dnnl-devel`. Both `builder` and `runner` derive from `base`, so
  they share one identical driver/oneDNN layer — versions can't drift and it's cached once.
- **`builder`** — adds Node.js (NodeSource) + `libssl-dev`, clones llama.cpp, and compiles
  with SYCL. Discarded from the final image.
- **`runner`** — `FROM base`, sets `LD_LIBRARY_PATH` for `libdnnl`, copies the binaries.

The Vulkan Dockerfile follows the same base/builder/runner shape and the same clone and UI
patterns as Intel: `ubuntu:resolute` base with an `apt upgrade`, Node.js (NodeSource) in the
`builder` for the source-built UI, and the same `git fetch --depth 1 origin "${LLAMA_CPP_COMMIT:-HEAD}"`
+ `checkout FETCH_HEAD` clone. It is simpler than Intel: no oneDNN, no AOT, single image, and its
GPU runtime (`libvulkan1`, `mesa-vulkan-drivers`, …) is installed in the `runner` stage rather
than `base`.

## Build arguments (Intel)

| Arg | Default | Effect |
|---|---|---|
| `ONEAPI_VERSION` | `2026.0` | Base image tag + oneDNN version + `CMAKE_PREFIX_PATH` |
| `BASE_IMAGE_PATCH_VERSION` | `0` | Base image patch component |
| `UBUNTU_VERSION` | `24.04` | Base image Ubuntu component |
| `NODE_VERSION` | `26` | NodeSource Node.js major version (must be ≥20 for the web UI) |
| `LLAMA_CPP_COMMIT` | *(empty)* | Commit to build; empty ⇒ fetch `HEAD`. Also the clone-layer cache key. |
| `GGML_SYCL_F16` | `OFF` | `-DGGML_SYCL_F16` |
| `GGML_SYCL_DEVICE_ARCH` | *(empty)* | When set, adds `-DGGML_SYCL_DEVICE_ARCH=<arch>` (AOT); when empty the flag is omitted entirely |

`ONEAPI_VERSION` is a global ARG re-declared in each stage that uses it (Docker requires the
re-declaration for it to be visible in `RUN`/`ENV` after `FROM`).

Vulkan's Dockerfile takes a subset: `LLAMA_CPP_COMMIT` and `NODE_VERSION` (same meaning; its base
is `ubuntu:resolute`, not parametrized).

## Key design decisions & gotchas

These are non-obvious and easy to break:

- **`LLAMA_CPP_COMMIT` does double duty.** It's both the checkout target and the build-cache
  key. The clone is `git fetch --depth 1 origin "${LLAMA_CPP_COMMIT:-HEAD}"` + `checkout FETCH_HEAD`,
  and the arg is *referenced* in the `RUN` so BuildKit actually invalidates the layer when it
  changes. CI passes the `ls-remote`-resolved HEAD for latest builds (freshness + caching) and
  the requested SHA for pinned builds. A constant or unreferenced value would silently serve a
  stale clone.
- **Web UI must be built from source.** llama.cpp's CMake builds the UI from the repo only if
  `npm` is on PATH; otherwise it downloads a prebuilt bundle from HuggingFace that lags the
  release by commits. Hence Node.js in the `builder` (both images). It requires Node ≥20 (Ubuntu's
  packaged 18 is rejected by the UI's `engines`), which is why NodeSource is used. On the plain
  `ubuntu` Vulkan base, `curl`/`gnupg`/`ca-certificates` must be installed *before* the NodeSource
  key import (the Intel base includes them).
- **AOT (`GGML_SYCL_DEVICE_ARCH=arl_h`) is slow to build but faster at runtime.** It compiles
  every kernel to native `arl_h` ISA at build time (~2–4× the JIT build time, dominated by a
  serial device-image link), but yields better codegen than runtime JIT (fuller optimization,
  spill reduction) — measurable TG *and* startup gains on Arrow Lake-H. The `arl-fp16` image is
  specialized for that arch; use the generic `intel`/`intel-fp16` tags for other Intel GPUs.
- **oneDNN is enabled by default** (`GGML_SYCL_DNN` auto-on once `find_package(DNNL)` succeeds via
  `CMAKE_PREFIX_PATH`) and accelerates the float matmul (GEMM) path. Its actual benefit depends on
  the GPU and the current state of the SYCL backend and can vary widely — benchmark before relying
  on it. Disable at runtime with `GGML_SYCL_DISABLE_DNN=1`. `libdnnl.so` is a `NEEDED` dependency
  of `libggml-sycl.so` (not `llama-server`) — check linkage with `ldd /app/libggml-sycl.so | grep dnnl`,
  not `ldd /app/llama-server`.
- **`GGML_BACKEND_DL=ON`** means backends are separate `dlopen`'d modules (`libggml-sycl.so`),
  so they won't appear in `ldd` of `llama-server`.

## CI/CD

Both workflows publish to GHCR and trigger on: push (path-filtered to the relevant Dockerfile +
workflow), a weekly `schedule` (Sun 04:00 UTC), and `workflow_dispatch`.

Intel workflow specifics:
- **Matrix** carries the bare suffix (`intel`, `intel-fp16`, `intel-arl-fp16`); the `Resolve
  build config` step prepends `latest-` (or `<short-sha>-` for pinned) to form the tag.
- **`commit` dispatch input** — empty builds latest HEAD; a SHA builds that commit, tags it
  `<short7>-<suffix>`, and runs **fully cacheless** (no import/export) so it can't pollute the
  latest cache. Distinguished by the `pinned` output of the resolve step.
- **Cache:** `type=gha`, `scope=<matrix.tag>`, `mode=max`, latest builds only. The weekly run
  adds `no-cache-filters: base` so the driver/oneDNN layer refreshes.
- Known limitation: base layers are duplicated across per-tag gha scopes; if the matrix grows and
  the 10 GB Actions cache cap bites, switching to `type=registry` cache (content-addressed dedup)
  is the intended lever.

Vulkan workflow mirrors the Intel one but single-image: same `commit` dispatch input and `Resolve
build config`/`pinned` logic (tags `latest-vulkan` or `<short7>-vulkan`, pinned builds cacheless).
It uses `mode=min` cache on `scope=vulkan` and `no-cache-filters: base,runner` on schedule (its
drivers live in the `runner` stage, not `base`).

## Building locally

```sh
# Latest master, generic Intel
docker build -f intel.Dockerfile -t llama.cpp:intel .

# FP16 + AOT for Arrow Lake-H
docker build -f intel.Dockerfile \
  --build-arg GGML_SYCL_F16=ON \
  --build-arg GGML_SYCL_DEVICE_ARCH=arl_h \
  -t llama.cpp:intel-arl-fp16 .

# A specific commit
docker build -f intel.Dockerfile \
  --build-arg LLAMA_CPP_COMMIT=<full-sha> \
  -t llama.cpp:intel-pinned .
```

Argless local builds fetch `HEAD` (the `${LLAMA_CPP_COMMIT:-HEAD}` fallback), so `docker build`
works without any build-args.

## Conventions when extending

- **New Intel variant:** add a matrix entry (bare suffix + `fp16`/`device_arch`) in
  `build-intel.yml`; the tag prefix is handled by the resolve step. No Dockerfile change needed —
  variants are driven entirely by build-args.
- **Keep `builder` and `runner` deriving from `base`** so the driver/oneDNN layer stays shared and
  version-consistent.
- **Vulkan vs Intel:** both share the source-built UI, commit pinning, and fetch-by-SHA clone.
  Intel-only features are oneDNN, AOT (`GGML_SYCL_DEVICE_ARCH`), and the multi-variant matrix —
  all SYCL-specific, so not applicable to Vulkan.
