import 'dart:convert';
import 'dart:typed_data';

import 'package:appproxy/data/proxy_backup_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('配置 + 二进制 ZIP 备份可完整还原', () {
    final config = Uint8List.fromList(utf8.encode('[{"proxyName":"A"}]'));
    final binary = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));
    final manifest = {
      'format': 1,
      'abi': 'arm64',
      'binary': {
        'fileName': 'sing-box-arm64',
        'size': binary.length,
        'version': 'sing-box version 1.15.0',
        'packageVersion': 'v0.0.3',
      },
    };
    final zip = ProxyBackupBundle.encode(
      configBytes: config,
      binaryBytes: binary,
      manifest: manifest,
    );
    expect(ProxyBackupBundle.isZip(zip), isTrue);

    final decoded = ProxyBackupBundle.decode(zip);
    expect(decoded, isNotNull);
    expect(decoded!.configBytes, config);
    expect(decoded.binaryBytes, binary);
    expect(decoded.binaryFileName, 'sing-box-arm64');
    expect(decoded.manifest['abi'], 'arm64');
    expect((decoded.manifest['binary'] as Map)['packageVersion'], 'v0.0.3');
  });

  test('仅配置打包（无二进制）', () {
    final config = Uint8List.fromList(utf8.encode('[]'));
    final zip = ProxyBackupBundle.encode(
      configBytes: config,
      manifest: {'format': 1},
    );
    final decoded = ProxyBackupBundle.decode(zip);
    expect(decoded, isNotNull);
    expect(decoded!.configBytes, config);
    expect(decoded.binaryBytes, isNull);
  });

  test('非 ZIP 内容不会误判', () {
    final json =
        Uint8List.fromList(utf8.encode('[{"proxyName":"A"}]'));
    expect(ProxyBackupBundle.isZip(json), isFalse);
  });

  test('解码非法 ZIP 返回 null', () {
    expect(ProxyBackupBundle.decode(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
