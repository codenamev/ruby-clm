#!/usr/bin/env python3
"""Record what the upstream Python engine answers for the fixture heads, so the
Ruby engine is checked end to end against clm.engine.Engine.

The encoder is replaced by the same deterministic fake the Ruby specs stub
(spec/support/fake_embeddings.rb): sin((byte sum + 1) * (i + 1)) * (1 + len).

    CLM_SRC=/path/to/Contrastive-LM/CLM/src venv/bin/python spec/fixtures/torch/generate_engine.py
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.environ["CLM_SRC"])
from clm.embedder import l2          # noqa: E402
from clm.engine import Engine        # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DIM = 16


class FakeEmbedder:
    def embed(self, texts):
        rows = []
        for t in texts:
            s = sum(t.encode()) % 65536
            v = np.array([math.sin((s + 1) * (i + 1)) * (1 + len(t)) for i in range(DIM)], dtype=np.float32)
            rows.append(l2(v))
        return np.stack(rows), sum(len(t) for t in texts)

    def healthy(self):
        return True


STATE = {"ticket": "Customer: my invoice was charged twice and nobody answers the phone!", "tier": "gold"}
QUESTIONS = {
    "urgency": {"type": "noul", "instructions": "Is this urgent?"},
    "department": {"type": "choice", "instructions": "Which team should handle this?",
                   "criteria": {"billing": "Charges, invoices, refunds", "technical": "Bugs and outages",
                                "sales": ""}},
    "frustration": {"type": "score", "instructions": "How frustrated is the customer?",
                    "criteria": ["Calm", "Frustrated", "Very angry"]},
}
RANK = ("What causes tides on Earth?",
        ["The Moon's gravitational pull.", "Photosynthesis in plants.", "Because the Earth is round."])


def main():
    out = {}
    for name in ("gelu_depth2", "silu_layernorm_residual"):
        engine = Engine(embedder=FakeEmbedder(), checkpoint=os.path.join(HERE, f"{name}.pt"), device="cpu",
                        action_cache="0")
        out[name] = {"answer": engine.answer(STATE, QUESTIONS),
                     "cool": engine.answer(STATE, QUESTIONS, temperature=0.5)["answers"],
                     "raw": engine.answer(STATE, QUESTIONS, model="clm-raw")["answers"],
                     "rank": engine.rank(RANK[0], RANK[1])}
    with open(os.path.join(HERE, "expected_engine.json"), "w") as fh:
        json.dump({"state": STATE, "questions": QUESTIONS, "rank": RANK, "cases": out}, fh, indent=1)


if __name__ == "__main__":
    main()
