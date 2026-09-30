# Local models

## What it is

The app runs Qwen2.5 GGUF weights through native llama.cpp. No prompt, record, or audio is sent to an inference service.

## How it works

The pinned runtime is llama.cpp `b10549`. Its release archive includes device and Mac frameworks; the preparation script builds an additional simulator framework from matching, checksummed source. These are assembled into `HarbourRuntime/Vendor/llama.xcframework`, ignored by Git. The app uses Metal on physical devices and CPU inference on the simulator. Context and sampler errors are reported rather than converted into an answer.

`ModelManager` chooses weights and streams a foreground URLSession download to a temporary file. The UI receives byte progress. A streaming SHA-256 and exact-size check must pass before atomic installation and creation of a verified marker. Cancelled and failed downloads remove temporary files. A later retry starts from the beginning; background transfer and resume data are not implemented. There is no automatic network fallback for a failed inference.

| Model | Revision | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Qwen2.5 0.5B Instruct Q4_K_M | `9217f5db79a29953eb74d5343926648285ec7e67` | 491400032 | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |
| Qwen2.5 1.5B Instruct Q4_K_M | `91cad51170dc346986eccefdc2dd33a9da36ead9` | 1117320736 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |

Downloads come from the official [Qwen Small repository](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) and [Balanced repository](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF). The hosts receive normal file-download metadata, such as IP address; health content is not included in the requests.

Automatic selection uses Small in the simulator. On a physical device it uses Balanced only with at least 8 GB of memory, nominal thermal state, and low-power mode off; otherwise Small. This is an initial heuristic, not a validated device benchmark policy. Manual selection remains available. Effort is a 96/160/256-token output budget, not a guarantee of reasoning quality. Only the active model has an inference context; switching frees the previous context.

## How to change it

Generation stops only after the outer JSON object is complete. `JSONEnvelope` tracks nesting, quoted strings, and escapes; a nested `arg` object's closing brace must not stop generation. The core planner still parses and validates the completed object against the original message. Runtime regression tests cover this independently of model quality.

Update filename, immutable revision, byte count, and checksum together in `ModelChoice`. A different model family also requires the correct prompt template; the current template is Qwen ChatML. Extend the CPU/Metal tests before changing the runtime. Never adapt arbitrary tool names into executable operations.

The first older runtime failed Metal startup on this Mac, and the first newer CLI process hit a teardown assertion when exiting before releasing its context. The current probe explicitly unloads the runtime before exiting. Simulator inference is tested separately from Mac Metal inference.

## Configuration

`scripts/prepare-runtime.sh` requires Xcode, CMake, curl, unzip, and shasum. `HARBOUR_RUNTIME_VENDOR` can override the output directory for clean setup testing. Runtime archive SHA-256: `636709d4a7b49ac7f2ed6dc8a4de3f278c257cac7248fe40d6a513f671e4bff4`. Source tarball SHA-256: `418ef98f058952c4f2e1fba0f77a73cbbfac2e5bf4146a0dc3202777ed5d9c1f`.

Download timeout: 30 minutes total, 60 seconds per request. Model storage is Application Support/Models and is excluded from iOS backup. Context is 2,048 tokens; threads are capped at four. Large inputs fail explicitly.

## Dependencies

Native [llama.cpp](https://github.com/ggml-org/llama.cpp/tree/b10549), CryptoKit, URLSession, and official Qwen weights. See [third-party notices](../THIRD_PARTY_NOTICES.md). Apple Intelligence is not required.
