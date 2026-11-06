<div align="center">

<img src="assets/app_icon.png" width="96" alt="Plana App">

# Plana App

**A third-party NovelAI client for Android** — a more comfortable mobile workspace for AI image generation

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mc5024/Plana-App?label=release)](https://github.com/mc5024/Plana-App/releases)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3ddc84?logo=android&logoColor=white)](#building)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)

[![Download latest APK](https://img.shields.io/github/v/release/mc5024/Plana-App?label=Download%20APK&style=for-the-badge&logo=android&logoColor=white&color=3ddc84)](https://github.com/mc5024/Plana-App/releases/latest)

[简体中文](README.md) · **English**

</div>

---

## Highlights

- **Prompt editor** A dedicated full-screen editor built for mobile, with completion candidates popping up at the bottom as you type.
  Prompts can be shown as plain text or as chips; the weight panel lets you raise, lower or clear weights, copy, disable, delete,
  and convert SD syntax

- **Tag completion & translation** Search tags and characters in Chinese or English; candidates come with Danbooru summaries
  and aliases, and tags are translated into Chinese automatically

- **Background generation** Generation keeps going when the app is in the background, with progress pinned in the notification
  shade and shown as a Live Update / status bar chip on Android 16

- **Queue & loop** Queue up several tag sets to generate one after another; loop generation runs for a set count or indefinitely,
  and can be paused at any time

- **Metadata import** The advanced import panel shows all metadata embedded in an image and lets you pick fields one by one;
  works with NAI stealth info as well as ComfyUI / A1111 metadata

- **Local gallery** Originals and parameter snapshots are kept on device and searchable by model and tag; on export, metadata
  can be kept, stripped or rewritten. Press-and-release to preview, drag from the filmstrip to the trash bar to delete,
  multi-select in the grid for batch actions; after deleting an image the neighboring one is shown.
  Filter by today, last 7 / 30 days, a specific date or a range, with draggable start and end dates in the range calendar

- **Libraries** The inspiration library stores prompts by character / style / scene and can generate preview images;
  the Vibe library imports and exports `.naiv4vibe` and manages encodings per model; the character reference library
  keeps the reference images you've used

- **Codex** Browse community-curated prompts, artist strings and collections, and add them to the generate page in one tap

- **Usage stats** Daily on-device accounting of image count and Anlas spent, with trend charts and per-day details

- **Prompt presets** Built-in presets match the official ones; create your own and choose whether they go before or after
  the positive prompt; presets are detected and stripped automatically when importing images

- **Toolbox** Convert whole prompts between SD and NAI weight syntax, with weight highlighting and direct import into the
  generate page; plus an image metadata viewer and editor

Everything you'd expect from the NAI web app — multiple characters with positions, Vibe Transfer, Precise Reference,
img2img, inpainting and outpainting, upscaling, resolution and cost estimates, token counts — is fully supported.

## Screenshots

| Generate | Prompt editor | Gallery |
|:---:|:---:|:---:|
| <img src="screenshots/generate.jpg" width="250" alt="Generate"> | <img src="screenshots/editor.jpg" width="250" alt="Prompt editor"> | <img src="screenshots/gallery.jpg" width="250" alt="Gallery"> |

| Codex | Metadata import | Usage stats |
|:---:|:---:|:---:|
| <img src="screenshots/codex.jpg" width="250" alt="Codex"> | <img src="screenshots/import.jpg" width="250" alt="Metadata import"> | <img src="screenshots/stats.jpg" width="250" alt="Usage stats"> |

## Usage

**Direct token connection — fully functional, no third-party service required.** Enter your own NovelAI token
(or sign in with your email and password) and requests go straight to NovelAI. Every feature listed above works this way;
this is the app's default mode.

### About Bot authorization

Some free extended features are currently offered through Bot authorization. Because server and quota resources are
limited, it is invite-only for now; we'll try to open it up further when we can.

Cloud backup and the public library will open once the server side is ready.

Authorization is entirely optional: without it, nothing in direct mode is affected. In the onboarding screen and in
「我的 → 账号与接入」 (Me → Account & Connection) you can switch to a self-hosted address at any time, or leave it blank
and not use it at all. The server is not part of this repository.

## Roadmap

| Plan | Description | Stage |
|---|---|---|
| **More platforms** | iOS is planned; other platforms are not yet on the roadmap | Planned |
| **Built-in image editing** | Integrate image editing models to edit images inside the app, no export to other tools needed | Long-term |
| **ComfyUI connector** | Use a self-hosted ComfyUI as the generation backend | Long-term |

## Community & feedback

QQ group: **1078261982**

Joining the QQ group does not grant Bot authorization, but feedback and suggestions are welcome there.

Please report bugs and feature requests via [Issues](https://github.com/mc5024/Plana-App/issues).

## Building

Requires Dart SDK ^3.12.2 (Flutter 3.44+); Android 7.0 (API 24) or later, compileSdk 36 (needed for Live Update progress).

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

The output is `build/app/outputs/apk/release/Plana-<version>-arm64-v8a.apk`; only arm64-v8a is built.

```bash
flutter analyze && flutter test
```

About 80k lines of Dart, 60 test files / 660 test cases. The tokenizer, Anlas formula, Vibe hash scheme,
NAI 5 payload contract and Argon2id derivation are all pinned by reference vectors, so any mismatch fails the tests.

## Credits & sources

This project stands on the following work.

### Data & upstream

| Source | Used for |
|---|---|
| [Danbooru](https://danbooru.donmai.us/) | Tag taxonomy and alias data |
| [Auto-NovelAI-Refactor](https://github.com/zhulinyv/Auto-NovelAI-Refactor) · zhulinyv | Tag list, popularity, categories and Chinese translations for the offline completion dictionary (`assets/danbooru.tsv`, bundled), taken from its `danbooru_tags_full_zh.csv` (GPL-3.0) |
| [DanbooruSearchOnline](https://github.com/SuzumiyaAkizuki/DanbooruSearchOnline) · SuzumiyaAkizuki | Online Chinese tag search, translations and one-line descriptions for completion |
| [quicktagcloud](https://novelai.quicktagcloud.com/) | All Codex data (entries / artist strings / collections / sample images). Read-only access; the data is not bundled, and this app neither modifies nor republishes Codex content. All content belongs to its original authors |
| [@huggingface/tokenizers](https://github.com/huggingface/tokenizers) | Reference implementation for the T5 tokenizer port |
| [nai5-prompting](https://github.com/Miint-Sunny/nai5-prompting) · Miint-Sunny | The comic section of the AI assistant presets (`assets/prompts/nai5.json`, bundled) (GPL-3.0) |
| [anime_censor_detection](https://huggingface.co/deepghs/anime_censor_detection) · deepghs | Detection model for auto-censoring (`assets/models/censor_n.ort`, bundled), i.e. its `censor_detect_v1.0_n`; this project only converted and quantized it (MIT) |
| [NovelAI](https://novelai.net/) · Anlatan | The image generation service itself |

Copyright of third-party content belongs to the respective authors. The bundled parts (tag dictionary, T5 vocabulary,
censor model, comic presets) are listed in [THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md); everything else is
only indexed or called at runtime.

### Open-source libraries

Built with [Flutter](https://flutter.dev) (BSD-3-Clause, © The Flutter Authors), using:

- **State & UI** — [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) ·
  [animations](https://pub.dev/packages/animations) ·
  [material_color_utilities](https://pub.dev/packages/material_color_utilities)
- **Networking & codecs** — [http](https://pub.dev/packages/http) ·
  [archive](https://pub.dev/packages/archive) ·
  [msgpack_dart](https://pub.dev/packages/msgpack_dart) ·
  [image](https://pub.dev/packages/image) ·
  [crypto](https://pub.dev/packages/crypto) ·
  [cryptography](https://pub.dev/packages/cryptography) (Blake2b + Argon2id, used for email/password sign-in) ·
  [unorm_dart](https://pub.dev/packages/unorm_dart)
- **Platform** — [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) ·
  [photo_manager](https://pub.dev/packages/photo_manager) ·
  [photo_manager_image_provider](https://pub.dev/packages/photo_manager_image_provider) ·
  [path_provider](https://pub.dev/packages/path_provider) ·
  [gal](https://pub.dev/packages/gal) ·
  [file_picker](https://pub.dev/packages/file_picker) ·
  [url_launcher](https://pub.dev/packages/url_launcher) ·
  [share_plus](https://pub.dev/packages/share_plus)
- **Build time** — [flutter_lints](https://pub.dev/packages/flutter_lints) ·
  [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)

All of the above are permissively licensed (BSD / MIT / Apache-2.0); see the per-package list in
[THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md). The full list is also available in the app under
「关于 → 开源许可」 (About → Open-source licenses).

## License

Copyright (C) 2026 Sora_Light

This project is released under GPL-3.0; see [LICENSE](LICENSE) for the full text. Modified versions you distribute
(including as an APK) must also be open-sourced under GPL-3.0. This program comes with no warranty.

Third-party content is not covered by this license and remains the property of its respective authors; see
[THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md).

## Disclaimer

This is an unofficial third-party client and is not affiliated with NovelAI (Anlatan). Users are responsible for
complying with NovelAI's Terms of Service. Any account issues, content issues or other consequences arising from
use of this app are the user's own responsibility.
