#!/usr/bin/env python3
"""Record what PyTorch computes with the released reference head, for the opt-in
spec/integration/reference_head_spec.rb (which runs only when the head is cached).

The inputs are a formula both sides can compute, so only the outputs are stored:
x[i][j] = sin((i + 1) * (j + 1) * 0.001), L2-normalised like encoder output.

    clm-download   # or CLM::Hub.download
    uv run --with torch --with numpy python spec/fixtures/torch/generate_reference.py
"""
import hashlib
import json
import math
import os

import torch
import torch.nn as nn

from generate import make_head

HERE = os.path.dirname(os.path.abspath(__file__))
CKPT = os.path.join(os.environ.get("CLM_CKPT_DIR", os.path.expanduser("~/.cache/clm")), "CLM_v0.1-8B.pt")
ROWS = 4


def main():
    ck = torch.load(CKPT, map_location="cpu")
    cfg = ck["cfg"]
    kw = dict(width=cfg["width"], depth=cfg["depth"], proj=ck.get("projection_dim", cfg.get("projection_dim")),
              activation=cfg["activation"], layernorm=cfg["layernorm"], residual=cfg["residual"],
              hidden=cfg["hidden_size"])
    sh, ah = make_head(**kw), make_head(**kw)
    sh.load_state_dict(ck["state_head"]); ah.load_state_dict(ck["action_head"])
    x = torch.tensor([[math.sin((i + 1) * (j + 1) * 0.001) for j in range(cfg["hidden_size"])] for i in range(ROWS)])
    x = nn.functional.normalize(x, dim=-1)
    with torch.no_grad():
        zs = nn.functional.normalize(sh(x), dim=-1)
        za = nn.functional.normalize(ah(x), dim=-1)
    with open(CKPT, "rb") as fh:
        sha256 = hashlib.sha256(fh.read()).hexdigest()
    with open(os.path.join(HERE, "reference_head.json"), "w") as fh:
        json.dump({"checkpoint_sha256": sha256, "torch": torch.__version__, "rows": ROWS,
                   "scale": float(torch.as_tensor(ck["logit_scale"]).float().exp().clamp(max=100.0)),
                   "projection_dim": kw["proj"], "n_params": sum(p.numel() for h in (sh, ah) for p in h.parameters()),
                   "states": zs.tolist(), "actions": za.tolist()}, fh)


if __name__ == "__main__":
    main()
