# Plana App 隐私政策

生效日期:2026-11-17

Plana App(下称「本 App」)是 NovelAI 图像生成的第三方客户端。本政策说明本 App 处理哪些数据、发往哪里。

## 存在你手机上的数据

生成的图片、提示词、灵感库、Vibe 库、设置等都保存在你的手机里。你填写的 NovelAI 账号凭据或 API 密钥只保存在手机上,只用于向 NovelAI 官方接口(或你自己填写的第三方接口)发出请求。

本 App 不含广告、统计或崩溃上报 SDK,不收集设备标识。

## 发往网络的数据

- **NovelAI / 你填写的接口**:出图、取词等请求直接发往 NovelAI 官方或你自己设置的接口。
- **Plana 服务(可选)**:只有在你绑定 Plana 账号后才会使用。你主动发起的云端备份(灵感库及其预览图、Vibe 库)会保存在 Plana 服务器及其使用的 Cloudflare R2 存储里;AI 助手经 Plana 模型通道发出的对话会转发给对应的模型服务;你发布到公共库的内容对其他用户公开。
- **Google 云端硬盘(可选)**:见下节。

## Google 云端硬盘备份

连接 Google 账号后,本 App 只申请 `https://www.googleapis.com/auth/drive.appdata` 这一项权限,用来在你的云端硬盘里读写本 App 自己的隐藏备份数据(灵感库、预览图、Vibe 库)。本 App 看不到、也不会读取或修改你云端硬盘里的其他文件。

- 备份数据从你的手机直接传到 Google,不经过 Plana 服务器;授权令牌由手机上的 Google Play 服务管理。
- 从 Google API 获得的数据只用于备份与恢复,不会出售、不会用于广告,也不会转交给第三方。本 App 对 Google API 所获信息的使用和转移遵守 [Google API 服务用户数据政策](https://developers.google.com/terms/api-services-user-data-policy),包括其中的「有限使用」要求。
- 你可以随时在本 App 里断开 Google 账号,或在 [Google 账号权限页面](https://myaccount.google.com/permissions) 撤销授权。要删除备份数据,可在 Google 云端硬盘的「设置 → 管理应用 → Plana App」里删除隐藏的应用数据。

## 联系

有问题请在 [GitHub Issues](https://github.com/mc5024/Plana-App/issues) 提出。本政策如有变动,会更新此页面并修改生效日期。

---

# Plana App Privacy Policy

Effective date: 2026-11-17

Plana App ("the App") is an unofficial client for NovelAI image generation. This policy explains what data the App handles and where it goes.

**On your device.** Generated images, prompts, the inspiration library, the Vibe library and settings are stored on your phone. Your NovelAI credentials or API key are stored only on your phone and are used only to call NovelAI (or an endpoint you configure yourself). The App contains no advertising, analytics or crash-reporting SDKs and does not collect device identifiers.

**Over the network.** Generation requests go directly to NovelAI or to the endpoint you configure. The optional Plana service is used only after you link a Plana account: cloud backups you start (inspiration library with previews, Vibe library) are stored on the Plana server and its Cloudflare R2 storage; AI assistant messages sent through the Plana model channel are forwarded to the corresponding model provider; content you publish to the public library is visible to other users.

**Google Drive backup.** When you connect a Google account, the App requests only the `https://www.googleapis.com/auth/drive.appdata` scope, to read and write its own hidden backup data in your Google Drive. It cannot see, read or modify any other files in your Drive. Backups go directly from your phone to Google, not through the Plana server; access tokens are managed by Google Play services on your phone. Data obtained from Google APIs is used only for backup and restore, is never sold, used for advertising or transferred to third parties. The App's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. You can disconnect at any time in the App or revoke access on your [Google Account permissions page](https://myaccount.google.com/permissions); to delete the backup data, go to Google Drive Settings → Manage apps → Plana App and delete its hidden app data.

**Contact.** Please open an issue on [GitHub](https://github.com/mc5024/Plana-App/issues). If this policy changes, this page and its effective date will be updated.
