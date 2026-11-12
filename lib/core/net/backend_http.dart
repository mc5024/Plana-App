import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 进程内共用的后端连接池(出图、查任务、标签补全/翻译都走它)。空闲 50s 关,
/// 赶在后端 nginx 的 keepalive_timeout(60s)之前。
final http.Client _sharedHttp = _SharedClient(
  IOClient(HttpClient()..idleTimeout = const Duration(seconds: 50)),
);

/// 后端请求用的客户端:`http.runWithClient` 换进来的替身优先,否则是共用池。
http.Client backendHttpClient() {
  final c = http.Client();
  if (c is IOClient) {
    c.close();
    return _sharedHttp;
  }
  return c;
}

/// 共用池的门面:`close()` 不关底层连接,各处照常 close 不影响别人。
class _SharedClient extends http.BaseClient {
  _SharedClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {}
}
