# tools/ —— 自动打码模型与运行时的重建流程

**简体中文** · [English](README.en.md)

自动打码用的检测模型和 ONNX Runtime 运行时都是**定制产物**,不是从 pub/Maven
直接拉的现成包。这里记录怎么从零重建它们。

平时**不需要跑这些** —— 产物已经在仓库里(`assets/models/censor_n.ort` 和
`android/ort-local-repo/`)。只有换模型或升 `flutter_onnxruntime` 时才需要。

## 为什么要定制

官方预编译的 `onnxruntime-android` 里,arm64 那份 `libonnxruntime.so` **一个人
就 19.2MB**(实测:不带它 APK 28.1MB,带它 46.5MB)。按本模型的算子表裁剪后
只有 **2.86MB**,APK 从 48.8MB 降到 33.4MB。

官方也出过精简包 `onnxruntime-mobile`,但**用不了**:冻结在 1.18.0 已弃用、
它的 Java API 与 `flutter_onnxruntime` 1.8.4(钉 ORT 1.23.0)不兼容、而且算子
表里没有 int8 需要的 `ConvInteger`。自编版对齐 1.23.0,三个问题一起解决。

## 前置

* **Modal 账号**(`~/.modal.toml` 已配置)。ORT 的 Android 构建在 Linux 上最顺,
  本机 Windows 没有 WSL/Docker,所以放 Modal 上跑,顺带能开十几核并行。
* Windows 上跑 `modal` 记得带 `PYTHONIOENCODING=utf-8`,否则 CLI 打印 `✓`
  会被 GBK 代码页噎住报 `'gbk' codec can't encode character`。

## 流程

### 1. 取模型并导出静态形状的 ONNX

模型:[`deepghs/anime_censor_detection`](https://huggingface.co/deepghs/anime_censor_detection)
的 `censor_detect_v1.0_n`(YOLOv8,二次元数据训练,MIT)。

HF 上那份 `model.onnx` 是**动态轴**导出的,直接用会在后续环节炸(符号维度
一路传到检测头)。必须从 `model.pt` 重新导一份静态的:

```python
from ultralytics import YOLO
YOLO("model.pt").export(format="onnx", imgsz=640, dynamic=False, simplify=True, opset=13)
```

### 2. 动态 int8 量化

```python
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic("censor_n.onnx", "censor_n_int8.onnx", weight_type=QuantType.QUInt8)
```

11.7MB → 3.4MB。实测与 fp32 的**类别分数通道最大差 0.00001**,检测结果等价。

> ⚠ 别换成 TFLite 那套动态范围量化 —— 实测在干净插画上会刷出 1800+ 个假框
> (YOLOv8 检测头对激活量化极敏感)。ORT 的权重量化才是近乎无损的那种。

### 3. 转 ORT 格式 + 生成算子表

精简构建**只吃 `.ort`**,不认 `.onnx`。用**与目标运行时同版本**的
onnxruntime 转(现在是 1.23.0):

```
python -m onnxruntime.tools.convert_onnx_models_to_ort censor_n_int8.onnx \
    --optimization_style Runtime --enable_type_reduction
```

两个参数都不能省,且与构建参数配套:

| 转换参数 | 对应构建参数 | 省了会怎样 |
|---|---|---|
| `--optimization_style Runtime` | `--minimal_build=extended` | 默认的 `Fixed` 会把 SiLU 融合成 `QuickGelu` 这个 contrib 算子 |
| `--enable_type_reduction` | `--enable_reduced_operator_type_support` | 少一截体积裁剪 |

产物:`*.with_runtime_opt.ort` → `assets/models/censor_n.ort`,
`*.required_operators_and_types.with_runtime_opt.config` → `censor_ops.config`。

### 4. 编运行时

```bash
PYTHONIOENCODING=utf-8 modal run tools/build_ort_aar.py
```

约 30–60 分钟。产物 AAR 放进 `android/ort-local-repo/` 的 Maven 布局里
(坐标与官方包同名,靠仓库顺序优先命中,见 `android/build.gradle.kts`)。

换模型后**算子表会变,必须重编运行时** —— 否则新模型用到的算子不在包里,
加载直接失败。
