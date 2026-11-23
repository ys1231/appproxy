import 'package:appproxy/data/proxy_paste_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sixFields = [
    PasteField.name,
    PasteField.type,
    PasteField.host,
    PasteField.port,
    PasteField.user,
    PasteField.pass,
  ];

  group('ProxyPasteProfile.parse', () {
    test('@ 分隔的六段内容映射到六个字段', () {
      const profile = ProxyPasteProfile(
        id: 't1',
        name: 'test',
        separator: '@',
        fields: sixFields,
      );
      final r = profile.parse(' 香港节点@HTTP@1.2.3.4@8080@user@pass ');
      expect(r[PasteField.name], '香港节点');
      expect(r[PasteField.type], 'http');
      expect(r[PasteField.host], '1.2.3.4');
      expect(r[PasteField.port], '8080');
      expect(r[PasteField.user], 'user');
      expect(r[PasteField.pass], 'pass');
    });

    test('# 与 | 分隔符按字面量切分', () {
      final hash = ProxyPasteProfile(
        id: 't2',
        name: 'hash',
        separator: '#',
        fields: sixFields,
      );
      expect(hash.parse('n#socks5#h#1080#u#p')[PasteField.type], 'socks5');

      final pipe = ProxyPasteProfile(
        id: 't3',
        name: 'pipe',
        separator: '|',
        fields: sixFields,
      );
      expect(pipe.parse('n|http|h|1|u|p')[PasteField.port], '1');
    });

    test('段数不匹配时抛出可读异常', () {
      const profile = ProxyPasteProfile(
        id: 't4',
        name: 'test',
        separator: '@',
        fields: sixFields,
      );
      expect(
        () => profile.parse('only@three@parts'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('字段数量不匹配'),
        )),
      );
    });

    test('多行时只识别第一行非空内容', () {
      const profile = ProxyPasteProfile(
        id: 't5',
        name: 'test',
        separator: '@',
        fields: sixFields,
      );
      final r = profile.parse('\n first@http@h@1@u@p \nsecond@...');
      expect(r[PasteField.name], 'first');
      expect(r[PasteField.host], 'h');
    });

    test('hostPort 组合字段拆分地址与端口（含 IPv6）', () {
      const profile = ProxyPasteProfile(
        id: 't6',
        name: 'hp',
        separator: '|',
        fields: [PasteField.name, PasteField.hostPort],
      );
      final r = profile.parse('node|1.2.3.4:8080');
      expect(r[PasteField.host], '1.2.3.4');
      expect(r[PasteField.port], '8080');

      final r6 = profile.parse('node|[::1]:1080');
      expect(r6[PasteField.host], '[::1]');
      expect(r6[PasteField.port], '1080');
    });

    test('完整 URL 识别（含账号密码与类型归一）', () {
      const profile = ProxyPasteProfile(
        id: 't7',
        name: 'url',
        separator: '',
        fields: [PasteField.url],
      );
      final r = profile.parse('socks5://user:pass@1.2.3.4:1080');
      expect(r[PasteField.type], 'socks5');
      expect(r[PasteField.host], '1.2.3.4');
      expect(r[PasteField.port], '1080');
      expect(r[PasteField.user], 'user');
      expect(r[PasteField.pass], 'pass');

      final https = profile.parse('https://proxy.example.com:443');
      expect(https[PasteField.type], 'http');
      expect(https[PasteField.host], 'proxy.example.com');
    });

    test('类型别名归一：SOCKS -> socks5', () {
      const profile = ProxyPasteProfile(
        id: 't8',
        name: 'test',
        separator: '@',
        fields: sixFields,
      );
      expect(profile.parse('n@SOCKS@h@1@u@p')[PasteField.type], 'socks5');
    });

    test('空内容抛异常', () {
      const profile = ProxyPasteProfile(
        id: 't9',
        name: 'test',
        separator: '@',
        fields: sixFields,
      );
      expect(() => profile.parse('   '), throwsA(isA<FormatException>()));
    });
  });

  test('默认规则包含 @ / # / | / URL 与服务商格式', () {
    final defaults = ProxyPasteProfiles.defaults();
    expect(defaults.map((e) => e.separator).toList(), containsAll(['@', '#', '|', '']));
    expect(defaults.where((e) => e.separator == '@').single.fields.length, 6);
    expect(defaults.any((e) => e.id == 'builtin_provider4'), isTrue);
    expect(defaults.any((e) => e.id == 'builtin_provider6'), isTrue);
  });

  test('服务商 6 段：识别 host/port/user/pass，忽略到期与地区', () {
    final profile = ProxyPasteProfiles.defaults()
        .firstWhere((e) => e.id == 'builtin_provider6');
    final r = profile.parse(
        'ch15.canghaiip.com|47890|qkab1123dl1000|6zi_20261123|2026-11-23|广西壮族自治区-柳州市');
    expect(r[PasteField.host], 'ch15.canghaiip.com');
    expect(r[PasteField.port], '47890');
    expect(r[PasteField.user], 'qkab1123dl1000');
    expect(r[PasteField.pass], '6zi_20261123');
    expect(r[PasteField.type], 'socks5');
    expect(r.containsKey(PasteField.name), isFalse);
  });

  test('服务商 4 段：host|port|user|pass', () {
    final profile = ProxyPasteProfiles.defaults()
        .firstWhere((e) => e.id == 'builtin_provider4');
    final r = profile.parse('1.2.3.4|1080|u|p');
    expect(r[PasteField.host], '1.2.3.4');
    expect(r[PasteField.port], '1080');
    expect(r[PasteField.user], 'u');
    expect(r[PasteField.pass], 'p');
    expect(r[PasteField.type], 'socks5');
  });
}
