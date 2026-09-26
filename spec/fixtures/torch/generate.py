#!/usr/bin/env python3
"""Regenerate the torch.save files the specs load: every tensor layout the loader
decodes (tensors.pt), and tiny projection-head checkpoints with the outputs PyTorch
computes for them (expected.json), so the Ruby heads are checked against the
reference implementation (clm/heads.py) rather than against themselves.

    python -m venv venv && venv/bin/pip install torch
    venv/bin/python spec/fixtures/torch/generate.py
"""
import json
import os

import torch
import torch.nn as nn

HERE = os.path.dirname(os.path.abspath(__file__))
HIDDEN = 16


def make_head(width, depth=2, proj=4, activation="gelu", layernorm=False, residual=False, hidden=HIDDEN):
    """Verbatim architecture of clm.heads.make_head."""
    act = {"gelu": nn.GELU, "relu": nn.ReLU, "silu": nn.SiLU}[activation]

    class Head(nn.Module):
        def __init__(self):
            super().__init__()
            self.inp = nn.Linear(hidden, width)
            self.hidden = nn.ModuleList(nn.Linear(width, width) for _ in range(depth - 2))
            self.norms = nn.ModuleList((nn.LayerNorm(width) if layernorm else nn.Identity())
                                       for _ in range(depth - 2))
            self.out = nn.Linear(width, proj)
            self.act = act()
            self.residual = residual

        def forward(self, x):
            x = self.act(self.inp(x))
            for lin, nrm in zip(self.hidden, self.norms):
                h = self.act(nrm(lin(x)))
                x = x + h if self.residual else h
            return self.out(x)

    return Head()


CASES = {
    "gelu_depth2": dict(cfg=dict(width=8, depth=2, activation="gelu", hidden_size=HIDDEN, projection_dim=4),
                        logit_scale=torch.tensor(2.5)),
    "silu_layernorm_residual": dict(cfg=dict(width=8, depth=4, activation="silu", layernorm=True, residual=True,
                                             hidden_size=HIDDEN, projection_dim=4),
                                    logit_scale=torch.tensor(10.0)),     # exp(10) is clamped to 100
    "relu_bfloat16": dict(cfg=dict(width=6, depth=3, activation="relu", hidden_size=HIDDEN),
                          projection_dim=4, logit_scale=1.0, dtype=torch.bfloat16),
    "gelu_float16": dict(cfg=dict(width=8, depth=3, activation="gelu", hidden_size=HIDDEN, projection_dim=4),
                         logit_scale=torch.tensor(3.0), dtype=torch.float16),
}


def tensors():
    """Every tensor layout and dtype the loader has to decode."""
    base = torch.arange(24, dtype=torch.float32).reshape(4, 6)
    torch.save({
        "transposed": base.t(),                 # non-contiguous view
        "sliced": base[1:3, ::2],               # offset + stride
        "shared_a": base, "shared_b": base[2],  # two views of one storage
        "scalar": torch.tensor(2.5), "long": torch.tensor([1, -2, 3], dtype=torch.int64),
        "half": torch.tensor([0.0, 1.0, -2.5, 65504.0, 6e-8, float("inf")], dtype=torch.float16),
        "bf16": torch.tensor([1.0, -3.140625, 1e30], dtype=torch.bfloat16),
        "double": torch.tensor([1.0 / 3], dtype=torch.float64),
        "flags": torch.tensor([True, False]),
        "meta": {"name": "x", "sizes": (1, 2)},
    }, os.path.join(HERE, "tensors.pt"))


def main():
    tensors()
    torch.manual_seed(0)
    inputs = torch.randn(3, HIDDEN)
    expected = {"inputs": inputs.tolist(), "cases": {}}
    for name, case in CASES.items():
        cfg = case["cfg"]
        proj = case.get("projection_dim", cfg.get("projection_dim", 4))
        kw = dict(width=cfg["width"], depth=cfg["depth"], proj=proj, activation=cfg.get("activation", "gelu"),
                  layernorm=cfg.get("layernorm", False), residual=cfg.get("residual", False), hidden=HIDDEN)
        sh, ah = make_head(**kw), make_head(**kw)
        for head in (sh, ah):          # non-trivial LayerNorm affine parameters
            for m in head.modules():
                if isinstance(m, nn.LayerNorm):
                    nn.init.normal_(m.weight, 1.0, 0.2); nn.init.normal_(m.bias, 0.0, 0.2)
        dtype = case.get("dtype", torch.float32)
        # float32 heads keep the OrderedDict (and its _metadata) that state_dict() returns
        cast = (lambda sd: sd) if dtype == torch.float32 else (lambda sd: {k: v.to(dtype) for k, v in sd.items()})
        ck = {"state_head": cast(sh.state_dict()), "action_head": cast(ah.state_dict()),
              "logit_scale": case["logit_scale"], "cfg": cfg, "step": 7}
        if "projection_dim" in case:
            ck["projection_dim"] = case["projection_dim"]
        torch.save(ck, os.path.join(HERE, f"{name}.pt"))

        # What clm.heads.HeadPair computes: load into float32 heads, project, L2-normalise.
        sh.load_state_dict(ck["state_head"]); ah.load_state_dict(ck["action_head"])
        with torch.no_grad():
            zs = nn.functional.normalize(sh(inputs), dim=-1)
            za = nn.functional.normalize(ah(inputs), dim=-1)
        scale = float(torch.as_tensor(case["logit_scale"]).float().exp().clamp(max=100.0))
        expected["cases"][name] = {"scale": scale, "projection_dim": proj, "states": zs.tolist(),
                                   "actions": za.tolist(),
                                   "n_params": sum(p.numel() for h in (sh, ah) for p in h.parameters())}
    with open(os.path.join(HERE, "expected.json"), "w") as fh:
        json.dump(expected, fh, indent=1)


if __name__ == "__main__":
    main()
