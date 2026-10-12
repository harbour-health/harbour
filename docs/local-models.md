# Local models

## What it is

The app runs Qwen3.5 2B and Qwen2.5 GGUF weights through native llama.cpp. Qwen3.5 2B is the default for new installs. No prompt, record, or audio is sent to an inference service.

## How it works

The pinned runtime is llama.cpp `b10549`. Its release archive includes device and Mac frameworks; the preparation script builds an additional simulator framework from matching, checksummed source. These are assembled into `HarbourRuntime/Vendor/llama.xcframework`, ignored by Git. The app uses Metal on physical devices and CPU inference on the simulator. Context and sampler errors are reported rather than converted into an answer.

Tool routing passes a GBNF grammar made by `ToolOutputGrammar.make(allowedTools:)`. It permits exactly `{"tool":"<name>","arg":""}` over the full tool catalog. The model chooses the action; source validation occurs afterward. The grammar controls JSON shape and enum membership, not user intent or answer quality. A grammar sampler filters tokens before greedy selection, and llama.cpp's `llama_sampler_sample` accepts each selected token. The sampler chain is freed on completion, error, or cancellation.

Ordinary conversation uses a second inference with no output grammar and `stopAtJSON: false`. It produces the actual assistant text instead of an empty routing argument or a fixed error response. Both stages use bounded recent history; see [Chat agent](chat-agent.md). Titles and visit summaries retain their separate output formats.

`ModelManager` chooses weights and streams a foreground URLSession download to a temporary file. The UI receives byte progress and an `isVerifying` state flag; it does not infer verification state from translated status text. A streaming SHA-256 and exact-size check must pass before atomic installation and creation of a verified marker. The flag clears when the operation completes, fails, or observes cancellation. Cancelled and failed downloads remove temporary files. A later retry starts from the beginning; background transfer and resume data are not implemented. There is no automatic network fallback for a failed inference.

| Model | Revision | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Qwen2.5 0.5B Instruct Q4_K_M | `9217f5db79a29953eb74d5343926648285ec7e67` | 491400032 | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |
| Qwen2.5 1.5B Instruct Q4_K_M | `91cad51170dc346986eccefdc2dd33a9da36ead9` | 1117320736 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |
| Qwen3.5 2B Q4_K_M | `f6d5376be1edb4d416d56da11e5397a961aca8ae` | 1280835840 | `aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223` |

Small and Balanced downloads come from the official [Qwen Small repository](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) and [Balanced repository](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF). Qwen3.5 2B uses Unsloth's [GGUF quantization](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/tree/f6d5376be1edb4d416d56da11e5397a961aca8ae) of the official [Qwen3.5-2B model](https://huggingface.co/Qwen/Qwen3.5-2B). The pinned file is `Qwen3.5-2B-Q4_K_M.gguf`, about 1.28 GB. Harbour uses its text model; no vision projector is downloaded. The hosts receive normal file-download metadata, such as IP address; health content is not included in the requests.

New installs and unrecognized model preferences default to Qwen3.5 2B. Saved Small, Balanced, and Automatic selections remain intact. Automatic selection uses Small in the simulator. On a physical device it uses Qwen3.5 2B only with at least 8 GB of memory, nominal thermal state, and low-power mode off; otherwise Small. This is an initial heuristic, not a validated device benchmark policy. Manual selection remains available. Effort sets routing budgets of 96/160/256 tokens and ordinary chat reply budgets of 256/512/768 tokens, not a guarantee of reasoning quality. Only the active model has an inference context; switching frees the previous context.

`ModelManager.generate` adds an app-language instruction to the existing ChatML system message. Generated titles and user-facing prose request Canadian French when the app's active localization is French, otherwise Canadian English. Required JSON keys, tool names, enum values, empty routing arguments, medicine names, source quotes, and extracted instructions stay exact. This preserves the grammar and source-grounding checks; it does not establish that every generated title will follow the instruction or that French medical extraction has been validated. The model remains subject to the original safety prompt and ordinary review screens.

`ModelManager` passes each model's `ModelPromptFormat` to the runtime. The runtime prepares the prompt before tokenization: Qwen2.5 keeps the existing ChatML prompt, while Qwen3.5 appends the canonical empty thinking block (`<think>\n\n</think>\n\n`) to its final assistant prefix, matching `enable_thinking=false`. This applies to routing, replies, titles, and visit summaries. The formatter leaves an already prepared prompt unchanged and rejects a Qwen3.5 prompt without a final assistant prefix. Harbour builds its messages directly; it does not execute the GGUF's stored chat template.

## How to change it

With the default `stopAtJSON: true`, generation stops after the outer JSON object is complete. Ordinary prose uses `false` and stops on end-of-generation or its output budget. `JSONEnvelope` tracks nesting, quoted strings, and escapes; a nested `arg` object's closing brace must not stop generation. The core planner still parses and validates the completed object against the original message. Runtime regression tests cover this independently of model quality.

Keep tool names in lowercase ASCII identifier form (`[a-z][a-z0-9_]*`); empty lists and unsafe names fail before a grammar is returned. Extend the caller's tool enum, full catalog, and execution validator together. Grammar restrictions ensure output shape and tool membership, but selection still requires core validation against the original message. Do not add generated arguments to the routing grammar. Factory regression tests cover the exact envelope and grammar injection rejection. The installed `llama.h` documents that `llama_sampler_sample` already calls `llama_sampler_accept`; accepting a second time would incorrectly advance grammar state.

Update filename, immutable revision, byte count, and checksum together in `ModelChoice`, and select the corresponding `ModelPromptFormat` there. Extend the formatter in `HarbourRuntime` when adding a different model template. Qwen3.5's non-thinking assistant prefix keeps hidden reasoning from consuming the bounded output budget or conflicting with the routing grammar. Extend the CPU/Metal tests before changing the runtime. Never adapt arbitrary tool names into executable operations.

Change output-language policy in `ModelManager.localizedPrompt` and localized display labels in the app resources. Keep `ModelChoice` and `Effort` raw values stable because they are persisted in user defaults. `Effort.title` supplies the translated display name. Never translate schema identifiers or source evidence to satisfy the language instruction.

The first older runtime failed Metal startup on this Mac, and the first newer CLI process hit a teardown assertion when exiting before releasing its context. The current probe explicitly unloads the runtime before exiting. Simulator inference is tested separately from Mac Metal inference.

## Configuration

`scripts/prepare-runtime.sh` requires Xcode, CMake, curl, unzip, and shasum. `HARBOUR_RUNTIME_VENDOR` can override the output directory for clean setup testing. Runtime archive SHA-256: `636709d4a7b49ac7f2ed6dc8a4de3f278c257cac7248fe40d6a513f671e4bff4`. Source tarball SHA-256: `418ef98f058952c4f2e1fba0f77a73cbbfac2e5bf4146a0dc3202777ed5d9c1f`.

Download timeout: 30 minutes total, 60 seconds per request. Model storage is Application Support/Models and is excluded from iOS backup. Context is 4,096 tokens; threads are capped at four. Large inputs fail explicitly.

The active Bundle localization, exposed by `L10n.isFrench`, chooses the generated prose language. No model or language preference changes the pinned download URLs, model verification, grammar, or local inference path.

`LocalModel.generate(file:prompt:maxTokens:grammar:stopAtJSON:promptFormat:)` defaults `promptFormat` to `.qwen25` and `grammar` to `nil`. Use `.qwen35` for Qwen3.5 generation. A supplied grammar starts from its `root` rule. Empty grammar strings, embedded NULs, and grammar allocation/parsing failures raise `ModelError.grammar`; they never silently fall back to unconstrained output. The output token budget can still end before an envelope is complete, which the core parser rejects.

On a Mac with the prepared runtime, run the local routing probe against a downloaded Qwen3.5 artifact with:

```sh
swift run --package-path HarbourRuntime model-probe /path/Qwen3.5-2B-Q4_K_M.gguf --qwen35
```

Without `--qwen35`, the probe retains the Qwen2.5 prompt format. `scripts/evaluate-simulator.sh SIMULATOR_UUID [OUTPUT_DIRECTORY]` runs Small, Balanced, and Qwen3.5 2B over the current routing fixtures at all three effort settings and saves `small.json`, `balanced.json`, and `qwen35.json`. These runners provide validation workflows; measured results and platform limitations belong in [evaluation](evaluation.md).

## Dependencies

Native [llama.cpp](https://github.com/ggml-org/llama.cpp/tree/b10549), CryptoKit, URLSession, official Qwen2.5 weights, and Unsloth's quantization of Qwen3.5 2B. See [third-party notices](../THIRD_PARTY_NOTICES.md). Apple Intelligence is not required.
