import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;

import '../store/app_stores.dart' show prefsStoreProvider;

/// 只读写本 App 自己在云端硬盘里的隐藏数据(appDataFolder)。
const kDriveScope = 'https://www.googleapis.com/auth/drive.appdata';

/// Google Cloud 里登记的 Web 客户端,安卓端拿它当 serverClientId。
const _kServerClientId =
    '934083553055-oqqtetb6os7k69dl5ccll3sks0b04khc.apps.googleusercontent.com';

const _kEmailKey = 'google_drive_email';

class DriveException implements Exception {
  DriveException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

final googleDriveAuthProvider = NotifierProvider<GoogleDriveAuth, String?>(
  GoogleDriveAuth.new,
);

/// 连着的 Google 账号(邮箱;null = 没连)。
class GoogleDriveAuth extends Notifier<String?> {
  static Future<void>? _init;

  @override
  String? build() => ref.read(prefsStoreProvider).get(_kEmailKey);

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(
    serverClientId: _kServerClientId,
  );

  /// 选账号并授权;用户取消返回 false。
  Future<bool> connect() async {
    try {
      await _ready();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [kDriveScope],
      );
      await account.authorizationClient.authorizeScopes(const [kDriveScope]);
      await ref
          .read(prefsStoreProvider)
          .write(key: _kEmailKey, value: account.email);
      state = account.email;
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return false;
      }
      throw DriveException(_signInError(e));
    }
  }

  /// 撤销授权并忘掉账号;云端硬盘里的备份不动。
  Future<void> disconnect() async {
    try {
      await _ready();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {} // 撤销失败(如没网)也照样在本机断开
    await ref.read(prefsStoreProvider).delete(key: _kEmailKey);
    state = null;
  }

  /// 访问令牌。[interactive] = 需要时弹授权,只能在前台由用户操作触发。
  Future<String> token({bool interactive = false}) async {
    final email = state;
    if (email == null) throw DriveException('没有连接 Google 账号');
    final ClientAuthorizationTokenData? t;
    try {
      await _ready();
      t = await GoogleSignInPlatform.instance
          .clientAuthorizationTokensForScopes(
            ClientAuthorizationTokensForScopesParameters(
              request: AuthorizationRequestDetails(
                scopes: const [kDriveScope],
                userId: null,
                email: email,
                promptIfUnauthorized: interactive,
              ),
            ),
          );
    } on GoogleSignInException catch (e) {
      throw DriveException(_signInError(e));
    }
    if (t == null) throw DriveException('Google 授权已失效,请重新连接');
    return t.accessToken;
  }

  /// 接口说令牌无效时丢掉缓存里的这个,下次重新取。
  Future<void> dropToken(String token) async {
    try {
      await GoogleSignInPlatform.instance.clearAuthorizationToken(
        ClearAuthorizationTokenParams(accessToken: token),
      );
    } catch (_) {}
  }

  static String _signInError(GoogleSignInException e) {
    final why = e.description ?? e.code.name;
    return switch (e.code) {
      GoogleSignInExceptionCode.canceled => '已取消',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google 登录不可用:$why',
      _ => 'Google 登录失败:$why',
    };
  }
}

/// [props] 是建文件时附上的 appProperties。
typedef DriveFile = ({
  String id,
  String name,
  int size,
  Map<String, String> props,
});

/// 云端硬盘隐藏数据区的文件接口。令牌失效自动换一次。
class DriveClient {
  /// [interactive] = 第一次取令牌时允许弹授权(用户刚点过按钮)。
  DriveClient(this._auth, {this._interactive = false});

  final GoogleDriveAuth _auth;
  bool _interactive;
  String? _token;
  final http.Client _http = http.Client();

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  /// 超过这个大小分段续传。
  static const _single = 5 << 20;

  /// 每段大小(须是 256KB 的整数倍)。
  static const _chunk = 8 << 20;

  void close() => _http.close();

  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> auth) request, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = _token ??= await _auth.token(interactive: _interactive);
      _interactive = false;
      final http.Response r;
      try {
        r = await request({'Authorization': 'Bearer $token'}).timeout(timeout);
      } on TimeoutException {
        throw DriveException('连接 Google 超时,请检查网络');
      } catch (_) {
        throw DriveException('连不上 Google,请检查网络');
      }
      if (r.statusCode == 401 && attempt == 0) {
        await _auth.dropToken(token);
        _token = null;
        continue;
      }
      if ((r.statusCode >= 200 && r.statusCode < 300) || r.statusCode == 308) {
        return r;
      }
      throw DriveException(_errText(r), status: r.statusCode);
    }
  }

  static String _errText(http.Response r) {
    var reason = '';
    try {
      final e = (jsonDecode(r.body) as Map)['error'] as Map;
      reason = '${((e['errors'] as List?)?.firstOrNull as Map?)?['reason']}';
    } catch (_) {}
    return switch (reason) {
      'storageQuotaExceeded' => 'Google 云端硬盘空间不足',
      'rateLimitExceeded' || 'userRateLimitExceeded' => 'Google 云端硬盘请求太频繁,稍后再试',
      _ => 'Google 云端硬盘出错(${r.statusCode})',
    };
  }

  static Duration _sendTimeout(int bytes) =>
      Duration(seconds: 60 + bytes ~/ 50000);

  /// 隐藏数据区的全部文件;[nameContains] 只列名字含它的。
  Future<List<DriveFile>> list({String? nameContains}) async {
    final out = <DriveFile>[];
    String? page;
    do {
      final q = {
        'spaces': 'appDataFolder',
        'fields': 'nextPageToken,files(id,name,size,appProperties)',
        'pageSize': '1000',
        if (nameContains != null) 'q': "name contains '$nameContains'",
        'pageToken': ?page,
      };
      final r = await _send(
        (h) => _http.get(
          Uri.parse('$_api/files').replace(queryParameters: q),
          headers: h,
        ),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in (j['files'] as List?) ?? const []) {
        if (f is! Map) continue;
        out.add((
          id: '${f['id']}',
          name: '${f['name']}',
          size: int.tryParse('${f['size']}') ?? 0,
          props: {
            for (final e in ((f['appProperties'] as Map?) ?? const {}).entries)
              '${e.key}': '${e.value}',
          },
        ));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  /// 剩余空间(字节);null = 不限。
  Future<int?> free() async {
    final r = await _send(
      (h) => _http.get(
        Uri.parse('$_api/about?fields=storageQuota(limit,usage)'),
        headers: h,
      ),
    );
    final q = (jsonDecode(r.body) as Map)['storageQuota'] as Map?;
    final limit = int.tryParse('${q?['limit']}');
    if (limit == null) return null;
    return limit - (int.tryParse('${q?['usage']}') ?? 0);
  }

  /// 新建文件,返回 id。[props] 附在文件上(列文件时能读到),[onSent] 报已传字节。
  Future<String> createBytes(
    String name,
    Uint8List bytes, {
    String mime = 'application/octet-stream',
    Map<String, String>? props,
    void Function(int sent)? onSent,
  }) => _create(
    name,
    bytes.length,
    (offset, n) async => Uint8List.sublistView(bytes, offset, offset + n),
    mime,
    props,
    onSent,
  );

  Future<String> createFile(
    String name,
    File file, {
    String mime = 'application/octet-stream',
    void Function(int sent)? onSent,
  }) async {
    final raf = await file.open();
    try {
      return await _create(
        name,
        await raf.length(),
        (offset, n) async {
          await raf.setPosition(offset);
          return raf.read(n);
        },
        mime,
        null,
        onSent,
      );
    } finally {
      await raf.close();
    }
  }

  Future<String> _create(
    String name,
    int size,
    Future<Uint8List> Function(int offset, int n) read,
    String mime,
    Map<String, String>? props,
    void Function(int sent)? onSent,
  ) async {
    final meta = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
      'appProperties': ?props,
    });
    if (size <= _single) {
      final boundary = 'plana${DateTime.now().microsecondsSinceEpoch}';
      final body =
          (BytesBuilder(copy: false)
                ..add(
                  utf8.encode(
                    '--$boundary\r\n'
                    'Content-Type: application/json; charset=UTF-8\r\n\r\n'
                    '$meta\r\n'
                    '--$boundary\r\nContent-Type: $mime\r\n\r\n',
                  ),
                )
                ..add(await read(0, size))
                ..add(utf8.encode('\r\n--$boundary--')))
              .takeBytes();
      final r = await _send(
        (h) => _http.post(
          Uri.parse('$_upload?uploadType=multipart&fields=id'),
          headers: {
            ...h,
            'Content-Type': 'multipart/related; boundary=$boundary',
          },
          body: body,
        ),
        timeout: _sendTimeout(body.length),
      );
      return _done(r, size, onSent);
    }

    final init = await _send(
      (h) => _http.post(
        Uri.parse('$_upload?uploadType=resumable&fields=id'),
        headers: {
          ...h,
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': mime,
          'X-Upload-Content-Length': '$size',
        },
        body: meta,
      ),
    );
    final session = init.headers['location'];
    if (session == null) throw DriveException('Google 云端硬盘没给上传地址');
    var offset = 0;
    var retries = 0;
    while (true) {
      final n = min(_chunk, size - offset);
      final chunk = await read(offset, n);
      final http.Response r;
      try {
        r = await _send(
          (h) => _http.put(
            Uri.parse(session),
            headers: {
              ...h,
              'Content-Range': 'bytes $offset-${offset + n - 1}/$size',
            },
            body: chunk,
          ),
          timeout: _sendTimeout(n),
        );
      } on DriveException catch (e) {
        // 断网 / 超时:问一下传到哪了,从那接着传
        if (e.status != null || ++retries > 3) rethrow;
        final s = await _send(
          (h) => _http.put(
            Uri.parse(session),
            headers: {...h, 'Content-Range': 'bytes */$size'},
          ),
        );
        if (s.statusCode != 308) return _done(s, size, onSent);
        offset = _rangeEnd(s.headers['range']);
        continue;
      }
      if (r.statusCode != 308) return _done(r, size, onSent);
      offset = _rangeEnd(r.headers['range']);
      onSent?.call(offset);
    }
  }

  static String _done(
    http.Response r,
    int size,
    void Function(int sent)? onSent,
  ) {
    onSent?.call(size);
    return '${(jsonDecode(r.body) as Map)['id']}';
  }

  /// 「bytes=0-524287」→ 下一段起点;没有 = 一个字节都没收到。
  static int _rangeEnd(String? range) {
    final end = int.tryParse(range?.split('-').last ?? '');
    return end == null ? 0 : end + 1;
  }

  Future<Uint8List> download(String id) async => (await _send(
    (h) => _http.get(Uri.parse('$_api/files/$id?alt=media'), headers: h),
    timeout: const Duration(minutes: 5),
  )).bodyBytes;

  Future<void> delete(String id) async {
    try {
      await _send(
        (h) => _http.delete(Uri.parse('$_api/files/$id'), headers: h),
      );
    } on DriveException catch (e) {
      if (e.status != 404) rethrow;
    }
  }
}
