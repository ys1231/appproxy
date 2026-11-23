import 'dart:convert';

import 'package:appproxy/data/common.dart';
import 'package:appproxy/data/ebpf_config_generator.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('未解析的已选 UID 仍保留，供 eBPF 使用', () {
      final selection = AppProxySelection();
      selection.replaceAll([
        const AppProxyEntry(
          uid: 99910230,
          userId: 999,
          packageName: '',
          multiUser: true,
        ),
      ], metadataReady: false);
      expect(selection.uids, [99910230]);
      expect(selection.metadataReady, isFalse);
      expect(selection.currentUserPackages, isEmpty);
    });
  });

  group('排除模式', () {
    test('AppSetings 持久化 include/exclude', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppSetings.getAppProxyExcludeMode(), isFalse);
      await AppSetings.setAppProxyExcludeMode(true);
      expect(await AppSetings.getAppProxyExcludeMode(), isTrue);
      await AppSetings.setAppProxyExcludeMode(false);
      expect(await AppSetings.getAppProxyExcludeMode(), isFalse);
    });

    test('eBPF exclude 模式写 exclude_uid，不写 include', () {
      final json = EbpfConfigGenerator.build(
        proxy: const {
          'proxyType': 'http',
          'proxyHost': '1.2.3.4',
          'proxyPort': '8080',
          'ebpfNetwork': 'tcp',
          'ebpfDataPlane': 'cgroup',
        },
        packageList: const ['com.tencent.mm'],
        uidList: const [99910230],
        exclude: true,
        selfPackage: 'cn.ys1231.appproxy',
      );
      final cfg = jsonDecode(json) as Map<String, dynamic>;
      final local = ((cfg['inbounds'] as List).first
          as Map<String, dynamic>)['local'] as Map<String, dynamic>;
      expect(local['exclude_uid'], [99910230]);
      expect(local.containsKey('include_uid'), isFalse);
      expect(local.containsKey('include_package'), isFalse);
      expect(local['exclude_package'], contains('cn.ys1231.appproxy'));
    });

    test('eBPF exclude 模式无勾选时全局代理（仅排除自己）', () {
      final json = EbpfConfigGenerator.build(
        proxy: const {
          'proxyType': 'http',
          'proxyHost': '1.2.3.4',
          'proxyPort': '8080',
          'ebpfNetwork': 'tcp',
          'ebpfDataPlane': 'cgroup',
        },
        packageList: const [],
        uidList: const [],
        exclude: true,
        selfPackage: 'cn.ys1231.appproxy',
      );
      final cfg = jsonDecode(json) as Map<String, dynamic>;
      final local = ((cfg['inbounds'] as List).first
          as Map<String, dynamic>)['local'] as Map<String, dynamic>;
      expect(local.containsKey('exclude_uid'), isFalse);
      expect(local.containsKey('include_uid'), isFalse);
      expect(local.containsKey('include_package'), isFalse);
      expect(local['exclude_package'], ['cn.ys1231.appproxy']);
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
