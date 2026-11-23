import 'package:appproxy/data/common.dart';
import 'package:appproxy/data/proxy_config_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxyConfigData.mergeAppend', () {
    test('保留本机配置与顺序，只追加备份中不存在的新配置', () {
      final current = <Map<String, dynamic>>[
        {'proxyName': 'A', 'proxyHost': '1.1.1.1'},
        {'proxyName': 'B', 'proxyHost': '2.2.2.2'},
      ];
      final backup = [
        {'proxyName': 'B', 'proxyHost': 'old'},
        {'proxyName': 'C', 'proxyHost': '3.3.3.3'},
        {'proxyName': 'D', 'proxyHost': '4.4.4.4'},
      ];
      final r = ProxyConfigData.mergeAppend(current, backup);
      expect(r.added, 2);
      expect(r.skipped, 1);
      expect(r.merged.map((e) => e['proxyName']).toList(), ['A', 'B', 'C', 'D']);
      // 同名时保留本机条目，不被备份覆盖
      expect(r.merged[1]['proxyHost'], '2.2.2.2');
    });

    test('备份全部重复时不新增也不跳过错误计数', () {
      final current = [
        {'proxyName': 'A'},
      ];
      final backup = [
        {'proxyName': 'A'},
        {'proxyName': 'A'},
      ];
      final r = ProxyConfigData.mergeAppend(current, backup);
      expect(r.added, 0);
      expect(r.skipped, 2);
      expect(r.merged.length, 1);
    });

    test('本机为空时追加结果等于备份', () {
      final backup = [
        {'proxyName': 'X'},
        {'proxyName': 'Y'},
      ];
      final r = ProxyConfigData.mergeAppend([], backup);
      expect(r.added, 2);
      expect(r.skipped, 0);
      expect(r.merged.length, 2);
    });
  });

  group('ProxyConfigData.applyEdit', () {
    test('改名：按旧名定位并更新为新名', () {
      final current = <Map<String, dynamic>>[
        {'proxyName': 'A', 'proxyHost': '1.1.1.1'},
        {'proxyName': 'B', 'proxyHost': '2.2.2.2'},
      ];
      final r = ProxyConfigData.applyEdit(
        current,
        {'proxyName': 'C', 'proxyHost': '3.3.3.3'},
        oldName: 'A',
      );
      expect(r.ok, isTrue);
      expect(r.renamed, isTrue);
      expect(r.sourceName, 'A');
      expect(r.list.map((e) => e['proxyName']).toList(), ['C', 'B']);
      expect(r.list.first['proxyHost'], '3.3.3.3');
    });

    test('改成已存在的其它配置名被拒绝', () {
      final current = <Map<String, dynamic>>[
        {'proxyName': 'A'},
        {'proxyName': 'B'},
      ];
      final r = ProxyConfigData.applyEdit(
        current,
        {'proxyName': 'B'},
        oldName: 'A',
      );
      expect(r.ok, isFalse);
      expect(r.list, same(current));
    });

    test('新增重名被拒绝', () {
      final current = <Map<String, dynamic>>[
        {'proxyName': 'A'},
      ];
      final r = ProxyConfigData.applyEdit(current, {'proxyName': 'A'});
      expect(r.ok, isFalse);
    });

    test('编辑时先删旧 eBPF 键再合并表单数据', () {
      final current = <Map<String, dynamic>>[
        {
          'proxyName': 'A',
          'proxyHost': 'old',
          'ebpfDnsMode': 'hijack',
          'ebpfNetwork': 'tcp',
          'otherKey': 'keep',
        },
      ];
      final r = ProxyConfigData.applyEdit(
        current,
        {'proxyName': 'A', 'proxyHost': 'new'},
        oldName: 'A',
      );
      expect(r.ok, isTrue);
      expect(r.renamed, isFalse);
      final item = r.list.single;
      expect(item['proxyHost'], 'new');
      expect(item.containsKey('ebpfDnsMode'), isFalse);
      expect(item.containsKey('ebpfNetwork'), isFalse);
      expect(item['otherKey'], 'keep');
    });
  });

  test('AppSetings.renameEbpfProfile 迁移设置侧 eBPF 标记', () async {
    SharedPreferences.setMockInitialValues({
      'ebpfProfiles': <String>['A', 'B'],
    });
    final after = await AppSetings.renameEbpfProfile('A', 'C');
    expect(after, {'C', 'B'});
    final reread = await AppSetings.getEbpfProfiles();
    expect(reread, {'C', 'B'});
  });
}
