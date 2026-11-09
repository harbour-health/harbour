# Optional Qwen 7B

## What it is

Build 11 adds Qwen2.5 7B Instruct Q4_K_M as a manual option for local chat, titles and doctor-visit summaries. Automatic remains the default and continues to choose Small or Balanced.

## How it works

Model selection and Downloads both include Qwen 7B. Selecting it alone does not transfer data. Download or the next inference fetches the two pinned shards, totalling 4.68 GB, with byte-weighted progress and streaming SHA-256 checks. Staging files are removed on failure or cancellation; all shards must be present and verified before the model is available. Removal clears both shards and markers. The composer displays Qwen 7B rather than accidentally labelling it Small.

The automatic recommendation is displayed independently of the user's manual selection. The increased-memory-limit entitlement requests a higher process allowance on supported Apple devices. It does not prove that the model will fit or perform acceptably on a particular phone.

## How to change it

See [local models](../local-models.md) for pinned artifacts, installation invariants and runtime settings. Extend `ModelChoice.assets` and its display labels together; preserve stored raw values. `ModelAssetTests` cover checksum/truncation rejection, missing or stale markers, incomplete multi-shard installations, removal and manual selection without changing the automatic policy. Sparse files test bookkeeping without downloading gigabytes; they are not inference evidence. `LargeModelUITests` exercises the real model picker and composer without downloading weights.

## Configuration

Version 0.1, build 11; existing bundle `com.matteopolak.harbour` and team `8SZZPTG649`. Two-hour foreground resource timeout per file, 60-second request timeout, 4,096-token context. The selected effort budgets and existing operation-specific sampling stay unchanged. No weights are added to the app bundle. The English and Canadian French model screens both include the memory note.

## Dependencies

Existing llama.cpp runtime with split-GGUF loading, URLSession, CryptoKit, official pinned Qwen assets, SwiftUI and App Store Connect internal testing. No new service or framework.

## Validation and delivery

Four targeted native tests passed in `/private/tmp/harbour-7b-options-final-20261109.xcresult`: three asset/selection tests and the real picker/composer UI test. The first UI run assumed Standard effort but inherited Extended from the simulator; the final test explicitly supplies Standard. The localization audit passes with 687 interface keys and 6 permission keys per language. Both official pinned shard checksums and lengths were independently refreshed from Hugging Face metadata without transferring weights. Internal distribution verification is pending. Physical-iPhone 7B memory, speed and thermal testing remain unverified; prior Mac model evaluations do not establish phone performance.
