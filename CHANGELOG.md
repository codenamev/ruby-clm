# Changelog

## [Unreleased]

Initial Ruby port of [Contrastive-LM/CLM](https://github.com/Contrastive-LM/CLM), with front doors
shaped like [ruby-laya](https://github.com/codenamev/ruby-laya)'s and behaviour that follows upstream
CLM where the two differ.

- `CLM::Decision` (`choice`, `score levels:`, `noul yes:/no:`, `model`, `define`, `decide`) and
  `CLM.ask(state)...decide`, reading answers as Ruby values: `triage.churn_risk?`,
  `triage.department == :billing`, `triage.urgency.label`.
- `predict(state, questions, **options)` on `CLM::Client` (HTTP to `clm-serve`) and `CLM::Engine`
  (in-process), the seam ruby-laya's clients answer; `CLM.client` is configurable.
- `CLM::Answer::Noul` / `Choice` / `Score` and `CLM::Result`, rendering the TypeSafe wire payload.
- `CLM::Engine`: in-process inference over an OpenAI-compatible embeddings server, with the
  `clm-raw` ablation, extra heads, hot reloading and a fixed-budget vector cache.
- Pure-Ruby loading of PyTorch projection-head checkpoints (`CLM::TorchFile`, `CLM::Pickle`),
  checked against PyTorch on fixtures and, opt-in, on the released head.
- Net::HTTP transport with `CLM::RetryPolicy` (ruby_decision_model's policy).
- `CLM::Server` (Rack) with the playground UI, `clm-serve` on Falcon (optional) and `clm-download`.
- `CLM::MockEngine` and `tools/playground_mock.rb` for working on the UI without a GPU.
