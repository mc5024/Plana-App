/// 检查更新(只检查,不下载不安装)。
///
/// 链路:GitHub Releases API 拿最新 release → 按语义化版本比 → 有新版就提示,
/// 用户点「去下载」跳外部浏览器打开 Release 页。**下载与安装交给浏览器和系统**,
/// 本应用不碰 —— 所以既不需要 `REQUEST_INSTALL_PACKAGES`,也不需要 FileProvider,
/// 更不需要自己校验安装包。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/app_info.dart';
import '../../core/store/prefs_store.dart';
import '../../core/util/log.dart';

/// 检查更新失败。`toString()` 直接是可展示文案。
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _channel = MethodChannel('plana/update');

/// 已安装包的真实版本(从系统读,不信 Dart 侧手抄的常量)。
class InstalledInfo {
  const InstalledInfo({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;

  /// 通道不可用(非 Android / 早期启动)时为空 —— 调用方据此跳过检查,
  /// 而不是拿空串去比出一个"有新版"。
  bool get isKnown => versionName.isNotEmpty;
}

/// GitHub 的一条 release。
class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.url,
    required this.prerelease,
  });

  /// 形如 `v1.0.0-beta.2`(比较时会剥掉前导 v)。
  final String tag;
  final String name;
  final String notes;

  /// Release 页地址,用户点「去下载」时用浏览器打开。
  final String url;
  final bool prerelease;

  /// 展示名:GitHub 上 release 标题常留空,回落到 tag。
  String get display => name.isNotEmpty ? name : tag;

  static GithubRelease? fromJson(Map<String, dynamic> j) {
    if (j['draft'] == true) return null; // 草稿对外不存在
    final tag = j['tag_name'] as String?;
    final url = j['html_url'] as String?;
    if (tag == null || tag.isEmpty || url == null || url.isEmpty) return null;
    return GithubRelease(
      tag: tag,
      name: (j['name'] as String?) ?? '',
      notes: (j['body'] as String?) ?? '',
      url: url,
      prerelease: j['prerelease'] == true,
    );
  }
}

/// 一次检查的结论。
class UpdateCheck {
  const UpdateCheck({required this.installed, this.release});

  final InstalledInfo installed;

  /// 比当前版本新的 release;没有(或拿不到)时为 null。
  final GithubRelease? release;

  bool get hasUpdate => release != null;
}

// ── 语义化版本比较 ───────────────────────────────────────────────────────

/// 比较两个语义化版本。→ 负数 / 0 / 正数。
///
/// **不能用字符串比。** `1.0.0-beta.10` 按字典序小于 `1.0.0-beta.9`,直接
/// 字符串比会让 beta.9 的用户永远收不到 beta.10。按 semver 2.0 规则:
/// 主次修订逐段按数字比;**带预发布标识的版本小于同号正式版**;预发布标识
/// 逐段比,纯数字段按数字、含字母段按 ASCII,数字段小于字母段。
int compareSemver(String a, String b) {
  final (coreA, preA) = _split(a);
  final (coreB, preB) = _split(b);

  for (var i = 0; i < 3; i++) {
    final c = (i < coreA.length ? coreA[i] : 0).compareTo(
      i < coreB.length ? coreB[i] : 0,
    );
    if (c != 0) return c;
  }

  // 1.0.0-beta.1 < 1.0.0
  if (preA.isEmpty && preB.isEmpty) return 0;
  if (preA.isEmpty) return 1;
  if (preB.isEmpty) return -1;

  for (var i = 0; i < preA.length && i < preB.length; i++) {
    final x = preA[i], y = preB[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final int c;
    if (nx != null && ny != null) {
      c = nx.compareTo(ny);
    } else if (nx != null) {
      c = -1; // 数字段 < 字母段
    } else if (ny != null) {
      c = 1;
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  // 前缀相同则段数少的更小(1.0.0-beta < 1.0.0-beta.1)
  return preA.length.compareTo(preB.length);
}

/// → (主次修订数组, 预发布标识数组)。剥前导 `v`,丢掉 `+build` 元数据。
(List<int>, List<String>) _split(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first; // build 元数据不参与比较
  final dash = s.indexOf('-');
  final core = dash < 0 ? s : s.substring(0, dash);
  final pre = dash < 0 ? '' : s.substring(dash + 1);
  return (
    [for (final p in core.split('.')) int.tryParse(p) ?? 0],
    pre.isEmpty ? const <String>[] : pre.split('.'),
  );
}

/// 该版本串是否是预发布(带 `-beta` 之类)。
bool isPrerelease(String v) => _split(v).$2.isNotEmpty;

// ── 检查 ─────────────────────────────────────────────────────────────────

/// 读已安装版本。通道不可用时返回空 [InstalledInfo],不抛。
Future<InstalledInfo> installedInfo() async {
  try {
    final m = await _channel.invokeMapMethod<String, dynamic>('info');
    if (m == null) return const InstalledInfo(versionName: '', versionCode: 0);
    return InstalledInfo(
      versionName: (m['versionName'] as String?) ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
    );
  } catch (e) {
    logd('[update] 读取已安装版本失败: $e');
    return const InstalledInfo(versionName: '', versionCode: 0);
  }
}

/// 拉 GitHub 上比 [current] 新的 release;没有则 null。
///
/// 用 `/releases` 列表而**不是** `/releases/latest` —— 后者会把预发布整个排除,
/// 而我们发的就是 `1.0.0-beta.x`,用它等于永远查不到东西。
///
/// [repo] 为空时直接返回 null。非 200 一律抛 [UpdateException]。
Future<GithubRelease?> fetchLatestRelease(
  String current, {
  String repo = kGithubRepo,
}) async {
  if (repo.isEmpty || current.isEmpty) return null;
  try {
    final resp = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repo/releases?per_page=10'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 429 ||
        (resp.statusCode == 403 &&
            resp.headers['x-ratelimit-remaining'] == '0')) {
      logd('[update] GitHub API 限流');
      throw const UpdateException('GitHub 查询次数已达上限,请稍后再试');
    }
    if (resp.statusCode != 200) {
      throw UpdateException('检查更新失败(HTTP ${resp.statusCode})');
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes));
    if (j is! List) throw const UpdateException('更新信息格式异常');
    return pickNewer(current, j);
  } on TimeoutException {
    throw const UpdateException('检查更新超时,请检查网络后重试');
  } on SocketException {
    throw const UpdateException('连不上 GitHub,请检查网络后重试');
  } on TlsException {
    throw const UpdateException('连不上 GitHub,请检查网络后重试');
  } on UpdateException {
    rethrow;
  } catch (e) {
    logd('[update] 检查更新异常: $e');
    throw const UpdateException('检查更新失败,请稍后重试');
  }
}

/// 从 release 列表里挑出比 [current] 新的那个(纯逻辑,单独抽出来可测)。
///
/// 已在正式版上的用户**不会**被推预发布 —— 否则装着 1.0.0 的人会被 1.1.0-beta.1
/// 拽回测试轨道。仍在 beta 上的人则照收 beta。
GithubRelease? pickNewer(String current, List<dynamic> releases) {
  final onPrerelease = isPrerelease(current);
  for (final r in releases) {
    if (r is! Map<String, dynamic>) continue;
    final rel = GithubRelease.fromJson(r);
    if (rel == null) continue;
    if (rel.prerelease && !onPrerelease) continue;
    if (compareSemver(rel.tag, current) > 0) return rel;
  }
  return null;
}

// ── 自动检查的节流 ───────────────────────────────────────────────────────

const _kLastCheckKey = 'update_last_check';

/// 记下"刚查过"。**不进 `PrefsStore.migrateKeys`** —— 那份名单只为「曾经在
/// secure storage 里、需要迁出」的键而设;这是个全新的键,从没在别处待过。
///
/// 收 [PrefsStore] 而不是 ref:`Ref` 与 `WidgetRef` 在 Riverpod 3 是两个类型,
/// 而调用方一个在 provider 里、一个在 State 里 —— 直接收 store 两边都能用。
Future<void> markUpdateChecked(PrefsStore prefs) async {
  try {
    await prefs.write(
      key: _kLastCheckKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  } catch (_) {}
}

/// 距上次检查是否已超过 [interval](默认 24h)。启动时自动检查用,避免每次
/// 冷启都打一次 GitHub。
bool shouldAutoCheck(
  PrefsStore prefs, {
  Duration interval = const Duration(hours: 24),
}) {
  final last = int.tryParse(prefs.get(_kLastCheckKey) ?? '');
  if (last == null) return true;
  return DateTime.now().millisecondsSinceEpoch - last > interval.inMilliseconds;
}
