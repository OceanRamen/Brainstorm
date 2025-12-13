# Repository Guidelines

Quick reference for contributing to Brainstorm.

## Project Structure & Module Organization
- Flow: `Core/Brainstorm.lua` (FFI) ↔ `Immolate.dll` (CPU) ↔ optional `ImmolateCUDA.dll` (experimental). UI lives in `UI/ui.lua`; logging helpers in `Core/logger*.lua`.
- Native sources: CPU entry in `ImmolateCPP/src/brainstorm_cpu.cpp`; experimental GPU path lives under `ImmolateCPP/src/gpu_experimental/` (entry `brainstorm_cuda.cpp`, `gpu/` kernels + loaders).
- Config and compatibility: `config.lua`, `lovely.toml`, `nativefs.lua`, `steamodded_compat.lua`. Scripts at repo root (`build_production.sh`, `deploy.sh`, `validate.sh`, `lint.sh`, `analyze_logs.lua`). Fixtures in `test_data/test_seeds.txt`.

## Build, Test, and Development Commands
- Primary build: `cd ImmolateCPP && ./build_cpu.sh` (CPU `Immolate.dll`); GPU via `./build_gpu.sh [--cpu-only|--with-tests]` producing `ImmolateCUDA.dll`.
- One-shot release pipeline: `./build_production.sh` (formats, lints, runs Lua smoke tests, builds CPU DLL, zips to `release/Brainstorm_v3.0.zip`; set `INCLUDE_GPU=1` to drop GPU artifacts into the zip).
- Quick checks: `stylua .` and `lua basic_test.lua`; broader Lua suite with `lua run_tests.lua` (skips missing files gracefully).
- Pre-flight: `./validate.sh` (DLL size, Lua syntax/formatting, optional Wine DLL probe; set `VALIDATE_GPU=1` to check the GPU DLL) then deploy from WSL with `./deploy.sh` to `%AppData%/Roaming/Balatro/Mods/Brainstorm` (`DEPLOY_GPU=1` to copy the experimental GPU binary).

## Architecture & FFI Safety
- DLL entry: `immolate.brainstorm(seed, voucher, pack, tag1, tag2, souls, observatory, perkeo)`; always `free_result()` on non-empty returns and wrap FFI calls in `pcall` to avoid crashing Balatro.
- GPU uses CUDA Driver API with primary-context management; code must compile/run on CPU when `GPU_ENABLED` is absent. Keep console output minimal; prefer logging to `brainstorm.log` when debugging.

## Coding Style & Naming Conventions
- Lua: Stylua (`stylua.toml`) — 2-space indent, ~80 cols, double quotes preferred. Gate debug output behind `Brainstorm.debug.enabled`, avoid globals, and return tables explicitly.
- C++: C++17 with RAII; guard GPU code with `#ifdef GPU_ENABLED`; minimal stdout noise. clang-format via `build_production.sh`/`lint.sh`.
- Naming: Lua locals/functions lower_snake; constants upper snake (`Brainstorm.VERSION`); C++ types PascalCase, globals `g_` per `src/brainstorm_cpu.cpp` (CPU) and `src/gpu_experimental/brainstorm_cuda.cpp` (GPU).

## Testing Guidelines
- Minimum before commit: `lua basic_test.lua` and `./lint.sh`; mention results in PRs. Run `./validate.sh` before deploying.
- GPU work: build with `./build_gpu.sh --with-tests` and run the emitted test harness/`ImmolateCPP/tests/cuda_drv_probe.cpp` to confirm driver access.
- Reuse fixtures from `test_data/test_seeds.txt` instead of hard-coding.

## Commit & Pull Request Guidelines
- Git history uses short, imperative subjects (`cleanup`, `fix logging`, `cuda works now`); keep that style, optionally scope-prefix (`core:`, `gpu:`, `ui:`).
- PRs: describe intent, list test commands (CPU and GPU paths if relevant), and note any DLL/kernel artifacts touched (`Immolate.dll`, `seed_filter.ptx`/`seed_filter.fatbin`, `gpu_worker.exe`). Include screenshots for UI changes.
- Do not commit `release/` artifacts; regenerate via the scripts above.
