<div align="center">

<img src="assets/app_icon.png" width="96" alt="Plana App">

# Plana App

**NovelAI 第三方 Android 客户端** —— 可能是最舒适的 AI 绘图移动创作端

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mc5024/Plana-App?label=release)](https://github.com/mc5024/Plana-App/releases)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3ddc84?logo=android&logoColor=white)](#构建)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)

</div>

---

## 亮点

- **提示词编辑器** 专为移动端设计的独占全屏编辑页,底部自动弹出补全候选;正文支持文本与芯片两种显示形态,
  权重面板提供权重增减与清除、复制、禁用、删除及 SD 语法转换

- **标签补全与翻译** 支持中英文搜词与搜角色,候选附 Danbooru 摘要与别名,标签自动翻译

- **后台生成** 退至后台继续出图不中断,进度常驻通知栏,并适配灵动岛与状态栏胶囊(Android 16)

- **队列与循环** 多组标签可连续入队依次生成;循环出图可指定张数或不限,随时暂停

- **NAI 5 适配** 角色画布定位、透明背景、Max 重绘等新特性均已适配

- **参数导入** 高级导入面板完整展示图片内嵌的元数据并支持逐项勾选,兼容 NAI 隐写信息与 ComfyUI / A1111 元数据

- **本地图库** 原图与参数快照本地留存,可按模型与标签检索,导出时元数据可保留、清除或改写;
  支持按住抬起预览、胶片条拖至垃圾条删除、网格多选批量操作

- **素材库** 灵感库按角色 / 画风 / 场景归类存储并可生成预览图;Vibe 库支持 `.naiv4vibe` 导入导出与逐模型编码管理;
  角色参考图库留存用过的参考图

- **法典图鉴** 可浏览社区整理的提示词、画师串与合集,一键加入创作页

- **用量统计** 本机按天记账,统计张数与消耗点数,提供趋势图与当日明细

- **提示词预设** 内置档位对齐官方,支持自建预设并指定拼接在正向词之前或之后;导入图片时自动识别并剥离

- **工具箱** SD ⇄ NAI 权重语法整串互转,结果带权重高亮并可直接导入创作页;另附图片元数据查看与改写

NAI 网页端的常规能力 —— 多角色与位置、Vibe Transfer、角色参考、图生图、局部重绘与扩图、
放大、分辨率与费用预估、token 读数 —— 均已完整支持。

## 截图

| 创作页 | 提示词编辑器 | 图库 |
|:---:|:---:|:---:|
| <img src="screenshots/generate.jpg" width="250" alt="创作页"> | <img src="screenshots/editor.jpg" width="250" alt="提示词编辑器"> | <img src="screenshots/gallery.jpg" width="250" alt="图库"> |

| 法典图鉴 | 参数导入 | 用量统计 |
|:---:|:---:|:---:|
| <img src="screenshots/codex.jpg" width="250" alt="法典图鉴"> | <img src="screenshots/import.jpg" width="250" alt="参数导入"> | <img src="screenshots/stats.jpg" width="250" alt="用量统计"> |

## 使用方式

**Token 直连 —— 完整可用,不依赖任何第三方服务。** 填入自己的 NovelAI Token(或用账号密码登录),
请求直接发往 NovelAI,上面列出的功能全部可用,这是本应用的默认形态。

应用另外内置了一个后端服务地址,用于内部使用的部分扩展能力,需授权。它是可选的 ——
直连模式下完全无需授权也可使用,引导页与「我的 → 账号与接入」里可随时改成自建地址或留空彻底不用,
但服务端不在本仓库内。

## 开发计划

| 计划 | 说明 | 阶段 |
|---|---|---|
| **多平台适配** | iOS 计划中;其他平台尚未规划 | 计划中 |
| **内置 AI 助手** | 应用内对话式协助:撰写与改写提示词、解释参数取值 | 远期 |
| **内置图像编辑** | 接入图像编辑模型,直接在应用内改图,不必导出到其他工具 | 远期 |
| **ComfyUI 连接器** | 接入自建 ComfyUI 作为出图后端 | 远期 |

## 交流与反馈

QQ 群:**1078261982**

Bug 与功能建议走 [Issues](https://github.com/mc5024/Plana-App/issues)。

## 构建

要求 Dart SDK ^3.12.2(Flutter 3.44 起);Android 7.0(API 24)以上,compileSdk 36(灵动岛进度需要)。

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

产物为 `build/app/outputs/apk/release/Plana-<版本>-arm64-v8a.apk`,仅出 arm64-v8a。

```bash
flutter analyze && flutter test
```

约 8 万行 Dart、60 个测试文件 / 660 个用例。分词器、Anlas 公式、Vibe 哈希口径、
NAI 5 载荷契约、Argon2id 派生均由参考向量钉住,改动对不上即失败。

## 致谢与出处

本项目站在这些工作之上。

### 数据与上游

| 来源 | 用途 |
|---|---|
| [Danbooru](https://danbooru.donmai.us/) | 标签体系与别名数据 |
| [Auto-NovelAI-Refactor](https://github.com/zhulinyv/Auto-NovelAI-Refactor) · zhulinyv | 离线补全词库(`assets/danbooru.tsv`,随包分发)的标签表、热度与绝大部分中文译名,取自其 `danbooru_e621_merged_with_zh.csv`(GPL-3.0) |
| [DanbooruSearchOnline](https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline) · SuzumiyaAkizuki | 增强补全的在线中文搜词、译名与一句话简介 |
| [quicktagcloud](https://novelai.quicktagcloud.com/) | 法典图鉴的全部数据(词条 / 画师串 / 合集 / 例图)。只读接入,数据不随包分发,本应用不修改也不发布法典内容,所有内容归原作者所有 |
| [@huggingface/tokenizers](https://github.com/huggingface/tokenizers) | T5 分词器移植的参照实现 |
| [NovelAI](https://novelai.net/) · Anlatan | 图像生成服务本身 |

第三方内容的版权归其各自作者所有;其中随包分发的部分(标签库、T5 词表)见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),其余仅作运行时索引与调用。

### 开源库

由 [Flutter](https://flutter.dev)(BSD-3-Clause,© The Flutter Authors)构建,并使用:

- **状态与界面** — [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) ·
  [animations](https://pub.dev/packages/animations) ·
  [material_color_utilities](https://pub.dev/packages/material_color_utilities)
- **网络与编解码** — [http](https://pub.dev/packages/http) ·
  [archive](https://pub.dev/packages/archive) ·
  [msgpack_dart](https://pub.dev/packages/msgpack_dart) ·
  [image](https://pub.dev/packages/image) ·
  [crypto](https://pub.dev/packages/crypto) ·
  [cryptography](https://pub.dev/packages/cryptography)(Blake2b + Argon2id,账号密码登录靠它) ·
  [unorm_dart](https://pub.dev/packages/unorm_dart)
- **平台能力** — [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) ·
  [photo_manager](https://pub.dev/packages/photo_manager) ·
  [photo_manager_image_provider](https://pub.dev/packages/photo_manager_image_provider) ·
  [path_provider](https://pub.dev/packages/path_provider) ·
  [gal](https://pub.dev/packages/gal) ·
  [file_picker](https://pub.dev/packages/file_picker) ·
  [url_launcher](https://pub.dev/packages/url_launcher) ·
  [share_plus](https://pub.dev/packages/share_plus)
- **构建期** — [flutter_lints](https://pub.dev/packages/flutter_lints) ·
  [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)

以上均为宽松许可(BSD / MIT / Apache-2.0),逐包清单见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md);应用内「关于 → 开源许可」亦有完整入口。

## 许可

Copyright (C) 2026 Sora_Light

本项目以 GPL-3.0 发布,全文见 [LICENSE](LICENSE)。分发修改版(含打包成 APK 分发)
须同样以 GPL-3.0 开源;本程序不作任何担保。

第三方内容不在本许可范围内,版权归各自作者所有,详见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 免责声明

本项目为非官方的第三方客户端,与 NovelAI (Anlatan) 无关联。用户需自行遵守
NovelAI 的服务条款。因使用本应用导致的账号问题、内容问题及任何其他后果,
均由用户自行承担。
