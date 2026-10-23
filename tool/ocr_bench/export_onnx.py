"""Convert IndicPhotoOCR's Kannada PARSeq checkpoint into phone-ready ONNX.

python3 export_onnx.py <IndicPhotoOCR_src_dir> <kannada.ckpt> <out_dir>
Writes kannada_parseq_fp32.onnx, kannada_parseq_int8.onnx (use this one on
the phone) and kannada_parseq_charset.txt (line i = output class i, 0 = end).
"""
import os
import sys

import onnx
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from onnxruntime.quantization.shape_inference import quant_pre_process

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parseq_kn  # noqa: E402

src, ckpt, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
model, tok, hp = parseq_kn.load(ckpt, src)
exp = parseq_kn.Exportable(model, tok).eval()
x = torch.randn(1, 3, 32, 128)
with torch.inference_mode():
    diff = (exp(x) - model(tok, x, max_length=hp['max_label_length'])).abs().max().item()
assert diff == 0.0, f'export wrapper differs from the original model: {diff}'

fp32 = os.path.join(out, 'kannada_parseq_fp32.onnx')
torch.onnx.export(exp, (x,), fp32, input_names=['image'], output_names=['logits'],
                  opset_version=17, dynamo=False, do_constant_folding=True)
onnx.checker.check_model(onnx.load(fp32))

pre = os.path.join(out, 'pre.onnx')
quant_pre_process(fp32, pre, skip_symbolic_shape=True)
quantize_dynamic(pre, os.path.join(out, 'kannada_parseq_int8.onnx'),
                 weight_type=QuantType.QInt8, per_channel=True)
os.remove(pre)

with open(os.path.join(out, 'kannada_parseq_charset.txt'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(tok._itos[:100]))
print('done:', sorted(os.listdir(out)))
