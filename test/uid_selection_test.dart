import 'dart:convert';

import 'package:appproxy/data/ebpf_config_generator.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppProxySelection', () {
    const mainApp = AppProxyEntry(
      uid: 10230,
      userId: 0,
      packageName: 'com.tencent.mm',
      multiUser: false,
    );
    const cloneApp = AppProxyEntry(
      uid: 99910230,
      userId: 999,
      packageName: 'com.tencent.mm',
      multiUser: true,
    );

    test('主应用与分身可分别选择，UID 列表独立', () {
      final selection = AppProxySelection();
      selection.replaceAll([cloneApp]);
      expect(selection.uids, [99910230]);
      expect(selection.hasNonCurrentUser, isTrue);
      expect(selection.hasCurrentUser, isFalse);
      expect(selection.currentUserPackages, isEmpty);

      selection.replaceAll([mainApp]);
      expect(selection.uids, [10230]);
      expect(selection.hasNonCurrentUser, isFalse);
      expect(selection.currentUserPackages, ['com.tencent.mm']);
    });

    test('只从本地拿到 UID 时 metadataReady=false，避免 VPN 用空包名启动', () {
      final selection = AppProxySelection();
      selection.replaceUids([10230, 99910230]);
      expect(selection.uids.toSet(), {10230, 99910230});
      expect(selection.metadataReady, isFalse);
      expect(selection.currentUserPackages, isEmpty);

      selection.replaceAll([mainApp, cloneApp]);
      expect(selection.metadataReady, isTrue);
      expect(selection.currentUserPackages, ['com.tencent.mm']);
    });
  });

  group('EbpfConfigGenerator include_uid', () {
    Map<String, dynamic> localOf(String json) {
      final cfg = jsonDecode(json) as Map<String, dynamic>;
      final inbound = (cfg['inbounds'] as List).first as Map<String, dynamic>;
      return inbound['local'] as Map<String, dynamic>;
    }

    const proxy = {
      'proxyType': 'http',
      'proxyHost': '1.2.3.4',
      'proxyPort': '8080',
      'proxyUser': '',
      'proxyPass': '',
      'ebpfNetwork': 'tcp',
      'ebpfDataPlane': 'cgroup',
    };

    test('有 UID 列表时写 include_uid，且不写 include_package', () {
      final json = EbpfConfigGenerator.build(
        proxy: proxy,
        packageList: ['com.tencent.mm'],
        uidList: [99910230],
        selfPackage: 'cn.ys1231.appproxy',
      );
      final local = localOf(json);
      expect(local['include_uid'], [99910230]);
      expect(local.containsKey('include_package'), isFalse);
    });

    test('无 UID 列表时保持 include_package 旧逻辑', () {
      final json = EbpfConfigGenerator.build(
        proxy: proxy,
        packageList: ['com.tencent.mm'],
        uidList: const [],
        selfPackage: 'cn.ys1231.appproxy',
      );
      final local = localOf(json);
      expect(local['include_package'], ['com.tencent.mm']);
      expect(local.containsKey('include_uid'), isFalse);
    });

    test('UID 与包名都为空时全局接管', () {
      final json = EbpfConfigGenerator.build(
        proxy: proxy,
        packageList: const [],
        uidList: const [],
        selfPackage: 'cn.ys1231.appproxy',
      );
      final local = localOf(json);
      expect(local.containsKey('include_uid'), isFalse);
      expect(local.containsKey('include_package'), isFalse);
    });
  });
}
