# CLM for Ruby

A Ruby port of [Contrastive-LM/CLM](https://github.com/Contrastive-LM/CLM): **Contrastive Language
Models**, a *System One* model for fast and generalizable decision-making.

CLM trains a state encoder and an action encoder with a contrastive (InfoNCE) objective, so that a
state is pulled toward the action that was taken and pushed away from all others. At inference time,
given a state and a set of candidate actions, CLM scores each candidate by how well its embedding
aligns with the state's, and a softmax over those scores *is* the answer distribution. Because states
and actions are embedded independently, both sides are cached and reused, which makes answers come
back in milliseconds.

This gem gives you, in idiomatic Ruby:

- **`CLM::Client`**: an HTTP client for the CLM System One API (TypeSafe-compatible), fiber-friendly
  so requests fan out concurrently under [Async](https://github.com/socketry/async).
- **`CLM::Engine`**: the in-process inference engine. It loads the upstream PyTorch projection-head
  checkpoints **without LibTorch** (a pure-Ruby `torch.save` reader and Numo matrices) and matches
  PyTorch's outputs to 1e-5.
- **`clm-serve`**: the API and its playground UI as a Rack app on [Falcon](https://github.com/socketry/falcon).

## Installation

```ruby
# Gemfile
gem "clm", github: "codenamev/ruby-clm"
```

Ruby 3.2 or newer. The engine and server also need an embedding server for the encoder (see below);
the client needs nothing but a running `clm-serve`.

## Quickstart

### Serve

```bash
# 1. the encoder: Qwen3-8B embeddings on a GPU (vLLM pooling server)
vllm serve Qwen/Qwen3-8B --served-model-name qwen3-8b --runner pooling --max-model-len 2048 --port 8090 &

# 2. the CLM API and playground on :8700 (downloads the 75 MB reference head on first run)
bundle exec clm-serve
```

States longer than 2048 tokens are truncated. For longer states raise both limits together, e.g.
`--max-model-len 8192` on `vllm serve` and `clm-serve --max-tokens 8192`.

### Ask typed questions about a state

```ruby
require "clm"

client = CLM::Client.new # CLM_BASE_URL (default http://127.0.0.1:8700), CLM_API_KEY

response = client.system_one("Customer: my invoice was charged twice and nobody answers the phone!") do |q|
  q.noul :urgency, "Is this urgent?"
  q.choice :department, "Which team should handle this?",
           billing: "Charges, invoices, refunds", technical: "Bugs and outages"
  q.score :frustration, "How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"]
end

response[:urgency].noul                  # => 0.41022   probability the statement is true
response[:department].choice             # => "billing"
response[:department].probabilities      # => {"billing" => 0.93878, "technical" => 0.06122}
response[:frustration].score             # => 1.98386   expected level, 0..2
response[:frustration].level             # => "Very angry"
response.usage.input_tokens              # => 38        (encoder tokens spent on cache misses)
response.latency_ms                      # => 58.1      (server-side)
```

Questions can also be objects or plain wire-format hashes, so a request written for TypeSafe replays
unchanged:

```ruby
client.system_one(state, {
  urgency: CLM::Noul.new(instructions: "Is this urgent?"),
  department: { type: "choice", instructions: "Which team?", criteria: { billing: "Charges", technical: "Bugs" } }
})
```

A `CLM::QuestionSet` is reusable, which suits an agent that asks the same questions of every state:

```ruby
TRIAGE = CLM::QuestionSet.build do |q|
  q.noul :urgent, "Is this urgent?"
  q.choice :team, "Which team should handle this?", billing: "Charges and refunds", technical: "Bugs"
end

client.system_one(ticket, TRIAGE)
```

With `CLM.configure` you can skip building a client:

```ruby
CLM.configure do |config|
  config.base_url = "https://clm.internal"
  config.api_key = ENV.fetch("CLM_API_KEY")
end

CLM.system_one(state) { |q| q.noul :done, "Did the agent finish the task?" }
```

### Rank candidates directly

`system_one` is built on one primitive: scoring candidates against a state. For free-form candidates
(best-of-N answers, tool names, next moves) use `rank`:

```ruby
client.rank("What causes tides on Earth?",
            ["The Moon's gravitational pull.", "Photosynthesis in plants.", "Because the Earth is round."])
# => [#<data CLM::Ranking rank=1, candidate="The Moon's gravitational pull.", prob=0.997>, ...]

client.rank(context, answers, question: "Which command fixes the build?", temperature: 0.5)
```

### Without a server: the engine

`CLM::Engine` answers the same calls in-process. It needs the encoder, but not `clm-serve`:

```ruby
engine = CLM::Engine.new(checkpoint: CLM::Hub.download) # reference head, fetched once into ~/.cache/clm
engine.rank("What causes tides on Earth?", ["The Moon's gravitational pull.", "Photosynthesis in plants."])
engine.system_one(state, TRIAGE)                        # the same SystemOneResponse the client returns
```

Because the client and the engine share an interface, code written against one runs on the other.

### Concurrency with Async

Answers take milliseconds, so agents ask many of them. The client's default adapter (Net::HTTP)
yields to Ruby's fiber scheduler, so calls made inside an Async reactor run concurrently, with no
threads and no extra configuration:

```ruby
require "async"
require "async/semaphore"

Sync do
  semaphore = Async::Semaphore.new(8) # at most 8 requests in flight
  tickets.map { |t| semaphore.async { client.system_one(t, TRIAGE) } }.map(&:wait)
end
```

The engine fans out the same way on its own: the state side and the candidate side of a request are
embedded concurrently, and an embedder call's batches run as concurrent tasks (`CLM::Concurrently`).
`clm-serve` runs on Falcon, so every request is a fiber and the time spent waiting on the encoder is
shared. See [`examples/async_fan_out.rb`](examples/async_fan_out.rb).

## Playground

`clm-serve` also serves a web UI at `/` (`http://localhost:8700/`). Write a state, add typed questions
and see CLM's answer distributions. Every request is also shown as JSON, `curl` and Ruby. A **Rank**
tab ranks any candidate set, and links are shareable. `clm-serve --no-ui` serves the API alone.

No GPU? `bundle exec ruby tools/playground_mock.rb` serves the real server and UI against a fake
character n-gram encoder. It is only for working on the UI: its numbers are lexical-overlap noise,
and the page says so in a banner.

## Configuration

| setting | environment | default |
| --- | --- | --- |
| `base_url` | `CLM_BASE_URL` | `http://127.0.0.1:8700` |
| `api_key` | `CLM_API_KEY` | none (the server also reads it to require `Authorization: Bearer <key>`) |
| `model` | | `clm-latest` |
| `request_timeout`, `max_retries`, `retry_interval` | | `300`, `2`, `0.1` |
| `embedder_url` | `CLM_EMB_URL` | `http://127.0.0.1:8090/v1/embeddings` |
| `embedder_model` | `CLM_EMB_MODEL` | `qwen3-8b` |
| `embedder_max_tokens` | `CLM_EMB_MAX_TOKENS` | `2048` |
| `embedder_api_key` | `CLM_EMB_API_KEY` | none |
| `checkpoint` | `CLM_CKPT` | the reference head, if downloaded |
| `checkpoint_dir` | `CLM_CKPT_DIR` | `~/.cache/clm` |
| `action_cache` | `CLM_ACTION_CACHE` | `0.02` |
| `logger` | `CLM_LOG_LEVEL` | `Logger` on `$stderr` at `info` |

Errors inherit from `CLM::Error`. Server responses map to `CLM::UnauthorizedError` (401),
`CLM::UnprocessableEntityError` (422, malformed request or unknown model), `CLM::BadGatewayError` (502,
encoder unreachable) and `CLM::ServerError`; `CLM::ConnectionError` means the server could not be
reached at all. The engine raises `CLM::InvalidRequestError`, `CLM::ModelNotFoundError`,
`CLM::EmbedderError` and `CLM::CheckpointError`.

## `clm-serve`

```
clm-serve [--port 8700] [--emb-url http://127.0.0.1:8090/v1/embeddings] [--emb-model qwen3-8b]
          [--max-tokens 2048] [--ckpt PATH] [--ckpt-dir DIR] [--model NAME=PATH ...]
          [--action-cache 0.02|512MiB|0] [--no-download] [--no-ui] [--cors]
```

`--ckpt PATH` serves your own head as `clm-latest` (default: the reference head in `~/.cache/clm/`,
downloaded if missing). `--ckpt-dir DIR` serves every `*.pt` there under its file stem, and
`--model NAME=PATH` adds one more. Checkpoints hot-reload when the file changes. `--cors` allows
browser requests from any origin. It is off by default, because otherwise any page could send the
API key header.

The server is a plain Rack app, so you can also host it yourself
([`examples/config.ru`](examples/config.ru)):

```ruby
run CLM::Server.new(CLM::Engine.new, api_key: ENV["CLM_API_KEY"])
```

`clm-download` fetches a checkpoint from the Hugging Face Hub and prints its path (`HF_TOKEN` is used
for gated repositories).

### The vector cache

An agent asks about a changing state but a mostly fixed set of actions, and it revisits states it
has already seen. Neither their embeddings nor their projections change while the head does not, so
the engine reserves a fixed memory budget at start-up and keeps them in it. `--action-cache` takes a
fraction of memory (`0.02`, the default), an absolute size (`512MiB`), or `0` to switch it off. The
budget is carved into one pool per vector width and never grows. Entries are keyed by head and
generation, so a hot-reloaded head stops matching rows its previous weights produced; eviction is
least-recently-used. `GET /health` reports occupancy and hit rate.

## API reference

### `POST /v1/systemone`

| field | |
| --- | --- |
| `state` | string, object or array (objects are rendered as `key: value` text, arrays as `- item` lines; never JSON, since the heads are trained on prose) |
| `model` | `clm-latest` (default), `clm-raw`, or any model from `GET /v1/models` |
| `questions` | `{id: Question}`, at least one |
| `temperature` | optional, `(0, 100]`, default 1; divides the logits before the softmax |

| question | required | answer |
| --- | --- | --- |
| `noul` | `instructions`; optional `criteria: {"true": …, "false": …}` | `{"noul": p_true}` |
| `choice` | `instructions`, `criteria: {option: description}` (each option is embedded as its description, or its key when the description is empty) | `{"choice", "confidence", "probabilities"}` |
| `score` | `instructions`, `criteria: [level0, level1, …]` (ordered, ≥ 2) | `{"score", "confidence", "legend", "probabilities"}` |

- `confidence` = top probability minus the mean of the others.
- `score` = expected level index; `legend` maps indices back to the rubric.
- `usage.input_tokens` counts encoder tokens spent on cache misses; `billing_units` is the number of questions.
- Errors are `{"detail": …}`: `401` bad key · `422` malformed request or unknown model · `502` embedder
  unreachable. `X-CLM-Latency-Ms` carries the server-side time.

### `POST /v1/rank`

`{"context": ..., "question": ..., "answers": [...]}` returns `{"model", "ranked": [{"rank",
"candidate", "prob"}, ...]}`, best first. The state head sees `context + question`, and the action head
sees each answer verbatim.

### `GET /v1/models` · `GET /health` · `GET /`

The served models, liveness (plus encoder reachability and cache statistics), and the playground.

## How the port works

| upstream (Python) | this gem (Ruby) |
| --- | --- |
| `clm.CLMClient`, `Noul` / `Choice` / `Score` | `CLM::Client`, `CLM::Noul` / `CLM::Choice` / `CLM::Score`, plus the `QuestionSet` builder |
| `clm.schema` | `CLM::Text` (prose rendering), `CLM::Question#candidates` / `#answer`, `CLM::Distribution` |
| `clm.embedder.Embedder` | `CLM::Embedder` (LRU cache, batches fetched concurrently) |
| `clm.heads.HeadPair` (torch) | `CLM::HeadPair` + `CLM::Head` (Numo), reading `.pt` files with `CLM::TorchFile` |
| `clm.heads.download` | `CLM::Hub` and `clm-download` |
| `clm.cache.VectorArena` | `CLM::VectorCache` |
| `clm.engine.Engine` | `CLM::Engine` |
| `clm.server` (FastAPI + uvicorn) | `CLM::Server` (Rack) + `clm-serve` (Falcon) |
| `tools/playground_mock.py` | `CLM::MockEngine` + `tools/playground_mock.rb` |

- **Checkpoints without LibTorch.** A `torch.save` file is a zip of a pickle plus raw tensor storages.
  `CLM::Pickle` is a small pickle VM that never resolves a global on its own. `CLM::TorchFile` allows
  only the constructors a checkpoint needs and rebuilds tensors (float32/64, float16, bfloat16,
  integer and bool; any strides) as Numo arrays. Nothing in a checkpoint is ever executed.
- **Heads run on the CPU** with Numo. Matrix products use BLAS when
  [numo-linalg](https://github.com/ruby-numo/numo-linalg) is loaded (`require "numo/linalg/autoloader"`)
  and C loops otherwise. The heads are small (about 20M parameters) and the vector cache means that
  repeated states and actions skip them.
- **Parity is tested, not assumed.** `spec/fixtures/torch/generate.py` writes real checkpoints with
  PyTorch and records their projections. `generate_engine.py` records what the upstream Python
  `Engine` answers for them. The specs check the Ruby heads and engine against both.

Not ported: training (`train/`), evaluation (`evaluation/`), preprocessing and the T-Rex example.
These are PyTorch research tooling rather than the inference library. Checkpoints they produce load
here unchanged.

## Development

```bash
bundle install
bundle exec rspec     # unit, parity and a Falcon integration spec
bundle exec rubocop
```

To regenerate the PyTorch fixtures, install `torch` and `numpy` in a virtualenv and run
`spec/fixtures/torch/generate.py`. Then run `generate_engine.py` with `CLM_SRC` pointing at a checkout
of the upstream `src/` directory.

## License

Apache 2.0, like the upstream project; see [LICENSE](LICENSE) and [NOTICE](NOTICE). The playground UI
is adapted from Contrastive-LM/CLM. The CLM-8B weights are released under Apache 2.0 on
[Hugging Face](https://huggingface.co/Contrastive-LM/CLM-v0.1-8B).

If you use CLM, please cite the original work:

```bibtex
@misc{kwok2026contrastivelanguagemodels,
  title={Contrastive Language Models: A System One Model for Fast and Generalizable Decision-Making},
  author={Jacky Kwok and Hangoo Kang and Tarun Suresh and Jon Saad-Falcon and Marco Pavone and Christopher Ré and Azalia Mirhoseini},
  year={2026},
  note={Notion Blog},
  url={https://contrastive-lm.notion.site}
}
```
