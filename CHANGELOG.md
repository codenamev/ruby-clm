# Changelog

## [Unreleased]

Initial Ruby port of [Contrastive-LM/CLM](https://github.com/Contrastive-LM/CLM).

- `CLM::Client`: the System One API client (`system_one`, `rank`, `models`, `healthy?`) with typed
  `Noul` / `Choice` / `Score` questions, a `QuestionSet` builder and status-mapped errors.
- `CLM::Engine`: in-process inference over an OpenAI-compatible embeddings server, with the
  `clm-raw` ablation, extra heads, hot reloading and a fixed-budget vector cache.
- Pure-Ruby loading of PyTorch projection-head checkpoints (`CLM::TorchFile`, `CLM::Pickle`).
- `CLM::Server` (Rack) with the playground UI, `clm-serve` on Falcon and `clm-download`.
- `CLM::MockEngine` and `tools/playground_mock.rb` for working on the UI without a GPU.
