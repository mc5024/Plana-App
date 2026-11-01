# tools/ — Rebuilding the auto-censor model and runtime

[简体中文](README.md) · **English**

The detection model and the ONNX Runtime used for auto-censoring are **custom builds**, not off-the-shelf packages
pulled from pub/Maven. This document records how to rebuild them from scratch.

You normally **don't need to run any of this** — the outputs are already in the repo (`assets/models/censor_n.ort` and
`android/ort-local-repo/`). It's only needed when switching models or upgrading `flutter_onnxruntime`.

## Why a custom build

In the official prebuilt `onnxruntime-android`, the arm64 `libonnxruntime.so` **alone is 19.2MB** (measured: APK is
28.1MB without it, 46.5MB with it). Trimmed to this model's operator set it's only **2.86MB**, and the APK drops from
48.8MB to 33.4MB.

There is also an official minimal package, `onnxruntime-mobile`, but it **can't be used**: it's frozen at the deprecated
1.18.0, its Java API is incompatible with `flutter_onnxruntime` 1.8.4 (pinned to ORT 1.23.0), and its operator set lacks
the `ConvInteger` that int8 needs. The custom build targets 1.23.0 and solves all three.

## Prerequisites

* **A Modal account** (`~/.modal.toml` configured). ORT's Android build is smoothest on Linux, and this Windows machine
  has no WSL/Docker, so it runs on Modal, which also gives a dozen-plus cores for parallel builds.
* When running `modal` on Windows, set `PYTHONIOENCODING=utf-8`; otherwise the `✓` printed by the CLI chokes the GBK
  code page with `'gbk' codec can't encode character`.

## Process

### 1. Get the model and export a static-shape ONNX

Model: `censor_detect_v1.0_n` from
[`deepghs/anime_censor_detection`](https://huggingface.co/deepghs/anime_censor_detection)
(YOLOv8, trained on anime data, MIT).

The `model.onnx` on HF is exported with **dynamic axes**, which breaks later steps (symbolic dimensions propagate all
the way into the detection head). A static one must be re-exported from `model.pt`:

```python
from ultralytics import YOLO
YOLO("model.pt").export(format="onnx", imgsz=640, dynamic=False, simplify=True, opset=13)
```

### 2. Dynamic int8 quantization

```python
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic("censor_n.onnx", "censor_n_int8.onnx", weight_type=QuantType.QUInt8)
```

11.7MB → 3.4MB. Measured against fp32, the **maximum difference in the class score channels is 0.00001**; detection
results are equivalent.

> ⚠ Don't switch to TFLite's dynamic range quantization — in testing it produced 1800+ false boxes on clean
> illustrations (the YOLOv8 detection head is extremely sensitive to activation quantization). ORT's weight
> quantization is the near-lossless kind.

### 3. Convert to ORT format and generate the operator config

The minimal build **only accepts `.ort`**, not `.onnx`. Convert with onnxruntime of **the same version as the target
runtime** (currently 1.23.0):

```
python -m onnxruntime.tools.convert_onnx_models_to_ort censor_n_int8.onnx \
    --optimization_style Runtime --enable_type_reduction
```

Neither flag can be omitted, and each pairs with a build flag:

| Conversion flag | Matching build flag | What happens without it |
|---|---|---|
| `--optimization_style Runtime` | `--minimal_build=extended` | The default `Fixed` fuses SiLU into `QuickGelu`, a contrib operator |
| `--enable_type_reduction` | `--enable_reduced_operator_type_support` | Less size trimming |

Outputs: `*.with_runtime_opt.ort` → `assets/models/censor_n.ort`,
`*.required_operators_and_types.with_runtime_opt.config` → `censor_ops.config`.

### 4. Build the runtime

```bash
PYTHONIOENCODING=utf-8 modal run tools/build_ort_aar.py
```

Takes about 30–60 minutes. The resulting AAR goes into the Maven layout under `android/ort-local-repo/`
(same coordinates as the official package, picked first by repository order; see `android/build.gradle.kts`).

After switching models **the operator set changes and the runtime must be rebuilt** — otherwise operators the new model
uses aren't in the package and loading fails outright.
