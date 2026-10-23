"""Load IndicPhotoOCR's Kannada PARSeq checkpoint without Lightning, run it,
and export a phone-friendly ONNX model.

The checkpoint also holds training state (optimizer, callbacks) whose
classes we don't have installed; those are replaced with stubs on load.
"""
import pickle
import sys
import types
import unicodedata

import numpy as np
import torch
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].endswith('.ckpt') else None


def _import_parseq(src_dir):
    sys.path.insert(0, src_dir)
    from IndicPhotoOCR.utils.strhub.data.utils import Tokenizer  # noqa: E402
    from IndicPhotoOCR.utils.strhub.models.parseq.model import PARSeq  # noqa: E402
    return Tokenizer, PARSeq


class _Stub:
    def __init__(self, *a, **k):
        pass

    def __setstate__(self, state):
        self.__dict__['_state'] = state

    def __call__(self, *a, **k):
        return _Stub()


class _LenientUnpickler(pickle.Unpickler):
    def find_class(self, module, name):
        try:
            return super().find_class(module, name)
        except Exception:
            return _Stub


_lenient = types.SimpleNamespace(Unpickler=_LenientUnpickler, load=pickle.load,
                                 __name__='lenient_pickle')


def load(ckpt_path, src_dir):
    Tokenizer, PARSeq = _import_parseq(src_dir)
    ckpt = torch.load(ckpt_path, map_location='cpu', weights_only=False, pickle_module=_lenient)
    hp = ckpt['hyper_parameters']
    hp = dict(hp) if not isinstance(hp, dict) else hp
    tok = Tokenizer(hp['charset_train'])
    model = PARSeq(
        num_tokens=len(tok), max_label_length=hp['max_label_length'], img_size=hp['img_size'],
        patch_size=hp['patch_size'], embed_dim=hp['embed_dim'], enc_num_heads=hp['enc_num_heads'],
        enc_mlp_ratio=hp['enc_mlp_ratio'], enc_depth=hp['enc_depth'], dec_num_heads=hp['dec_num_heads'],
        dec_mlp_ratio=hp['dec_mlp_ratio'], dec_depth=hp['dec_depth'], decode_ar=hp['decode_ar'],
        refine_iters=hp['refine_iters'], dropout=hp['dropout'],
    )
    sd = {k[len('model.'):]: v for k, v in ckpt['state_dict'].items() if k.startswith('model.')}
    missing, unexpected = model.load_state_dict(sd, strict=True), None
    model.eval()
    return model, tok, hp


def preprocess(img: Image.Image, size=(32, 128)) -> np.ndarray:
    """Same as IndicPhotoOCR: RGB, bicubic resize to 32x128, scale to [-1, 1]."""
    img = img.convert('RGB').resize((size[1], size[0]), Image.BICUBIC)
    x = np.asarray(img, dtype=np.float32) / 255.0
    x = (x - 0.5) / 0.5
    return x.transpose(2, 0, 1)[None]  # 1x3xHxW


def decode_logits(logits: np.ndarray, tok) -> tuple[str, float]:
    """Greedy decode: argmax per position, stop at <eos> (id 0)."""
    z = logits[0]
    z = z - z.max(-1, keepdims=True)
    probs = np.exp(z) / np.exp(z).sum(-1, keepdims=True)
    ids = probs.argmax(-1)
    out, conf = [], 1.0
    for pos, i in enumerate(ids):
        conf *= float(probs[pos, i])
        if i == tok.eos_id:
            break
        out.append(tok._itos[i])
    return unicodedata.normalize('NFC', ''.join(out)), conf


class Exportable(torch.nn.Module):
    """PARSeq inference with a fixed number of decode steps (no data-dependent
    early exit), batch size 1, so it traces into a static ONNX graph.
    Output: logits [1, max_len+1, num_classes]. Decode on device with argmax,
    stopping at class 0 (<eos>)."""

    def __init__(self, model, tok):
        super().__init__()
        self.m = model
        self.bos, self.pad, self.eos = tok.bos_id, tok.pad_id, tok.eos_id

    def forward(self, images):
        m = self.m
        steps = m.max_label_length + 1
        memory = m.encode(images)
        pos_queries = m.pos_queries[:, :steps]
        tgt_mask = query_mask = torch.triu(torch.ones((steps, steps), dtype=torch.bool), 1)
        tgt_in = torch.full((1, steps), self.pad, dtype=torch.long)
        tgt_in[:, 0] = self.bos
        logits = []
        for i in range(steps):
            j = i + 1
            out = m.decode(tgt_in[:, :j], memory, tgt_mask[:j, :j],
                           tgt_query=pos_queries[:, i:j], tgt_query_mask=query_mask[i:j, :j])
            p = m.head(out)
            logits.append(p)
            if j < steps:
                tgt_in[:, j] = p[:, 0].argmax(-1)
        logits = torch.cat(logits, dim=1)
        if m.refine_iters:
            qmask = query_mask.clone()
            qmask[torch.triu(torch.ones(steps, steps, dtype=torch.bool), 2)] = False
            bos = torch.full((1, 1), self.bos, dtype=torch.long)
            for _ in range(m.refine_iters):
                tgt_in = torch.cat([bos, logits[:, :-1].argmax(-1)], dim=1)
                pad_mask = (tgt_in == self.eos).int().cumsum(-1) > 0
                out = m.decode(tgt_in, memory, tgt_mask, pad_mask, pos_queries, qmask[:, :steps])
                logits = m.head(out)
        return logits
