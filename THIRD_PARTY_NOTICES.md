# 第三方组件与许可

**简体中文** · [English](THIRD_PARTY_NOTICES.en.md)

Plana 使用了下列第三方组件。相关许可要求在分发时保留版权声明与免责条款,
本文件即为该声明的载体。

> 1.0.6 起本地超分(ncnn-vulkan / Real-ESRGAN / stb / Upscayl 模型)整条下线,
> 相关组件与权重下载链路一并移除,故本文件不再列出它们。

> 分发本应用(APK / 应用商店 / 侧载包)时,请连同本文件一并提供,或在应用内「关于」页
> 提供等效的开源许可入口。

---

## Dart / Flutter 依赖

全部经 pub.dev 分发,许可均为宽松型(无 GPL 系):

| 许可 | 包 |
|---|---|
| BSD | `animations` · `crypto` · `flutter_secure_storage` · `gal` · `http` · `path_provider` · `share_plus` · `url_launcher` |
| MIT | `archive` · `file_picker` · `flutter_onnxruntime` · `flutter_riverpod` · `image` · `msgpack_dart` · `unorm_dart` |
| Apache-2.0 | `cryptography` · `material_color_utilities` · `photo_manager` · `photo_manager_image_provider` |

Flutter SDK 及其自带组件遵循 BSD 3-Clause(Copyright 2014 The Flutter Authors)。
完整的依赖许可清单可由 `flutter build` 生成的 `LICENSE` 汇总文件获得,
应用内亦可通过 `showLicensePage()` 展示。

仅构建期使用、不进包的依赖(`flutter_lints`、`flutter_launcher_icons`)不在此列 ——
本文件是随包分发的声明载体,只覆盖真正打进 APK 的东西。

---

## 随包分发的数据文件

`assets/` 下有四份**非本项目创作**的数据,随 APK 一同分发:

| 文件 | 出处 | 许可 |
|---|---|---|
| `danbooru.tsv` | 标签表、热度、类目与中文译名取自 [zhulinyv/Auto-NovelAI-Refactor](https://github.com/zhulinyv/Auto-NovelAI-Refactor) 的 `assets/danbooru_tags_full_zh.csv`,上游已不收录的少量旧 tag 沿用其早先的 `danbooru_e621_merged_with_zh.csv`;标签体系与别名归 [Danbooru](https://danbooru.donmai.us/) | 上游项目为 **GPL-3.0**,与本项目同许可,再分发合规 |
| `t5_tokenizer.json` | NovelAI 的 T5 分词器词表,字节级原样拷贝 | 版权归 Anlatan;本项目仅为 token 计数而调用,不作他用 |
| `models/censor_n.ort` | 自动打码的检测模型,[deepghs/anime_censor_detection](https://huggingface.co/deepghs/anime_censor_detection) 的 `censor_detect_v1.0_n`。本项目只做了格式转换与量化(静态导出 → 动态 int8 → ORT 格式),**权重未经再训练** | **MIT**(权重仓库)。另见下方关于 YOLOv8 的说明 |
| `prompts/nai5.json` 的 `comic_composition` / `mode_comic` 两段 | AI 助手预设的漫画部分,取自 [Miint-Sunny/nai5-prompting](https://github.com/Miint-Sunny/nai5-prompting) | 上游项目为 **GPL-3.0**,与本项目同许可,再分发合规 |

法典图鉴(quicktagcloud)的数据**不随包分发**,运行时只读拉取,故不在此列。

### 关于检测模型的 YOLOv8 血统

该模型是用 [Ultralytics](https://github.com/ultralytics/ultralytics) 的 YOLOv8
训练的,而 Ultralytics 的代码是 **AGPL-3.0**;权重仓库自身标注 MIT。Ultralytics
主张"用其代码训练/导出的模型受 AGPL-3.0 约束",这一主张在业界有争议,本项目
不做法律判断。

就本项目而言这不构成问题:**本应用整体已是 GPL-3.0 且开源**,而 GPL-3.0 明确
允许与 AGPL-3.0 作品结合(GPLv3 §13)。AGPL 特有的"网络交互需提供源码"条款
针对的是通过网络向用户提供服务的场景,本应用的检测**完全在设备本地运行**,
不经任何服务端。

Ultralytics 的代码本身**不随包分发**,仅在离线转换模型时用过一次
(见 `tools/README.md`)。

---

## 随包分发的原生库

| 库 | 出处 | 许可 |
|---|---|---|
| ONNX Runtime(`libonnxruntime.so` / `libonnxruntime4j_jni.so`) | [microsoft/onnxruntime](https://github.com/microsoft/onnxruntime) v1.23.0。**本项目自行编译**的精简构建:只含本应用模型所需的 17 个算子,`.so` 从官方全量包的 19.2MB 降到 2.86MB。构建脚本与完整流程见 `tools/`,产物 AAR 在 `android/ort-local-repo/` | **MIT**(Copyright (c) Microsoft Corporation) |

自编只改变了**包含哪些算子**,未修改任何源码。

Dart 侧的绑定 `flutter_onnxruntime` 为 **MIT**(Copyright (c) 2025 MASIC AI),
已计入上文 Dart 依赖清单。
