import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 粘贴识别可映射的目标字段。
///
/// 除基础字段外多了两个组合字段：
///  - [hostPort]：把 `host:port` 拆成 proxyHost/proxyPort（支持 `[IPv6]:port`）
///  - [url]：解析完整代理 URL，如 `socks5://user:pass@1.2.3.4:1080`
class PasteField {
  static const String name = 'proxyName';
  static const String type = 'proxyType';
  static const String host = 'proxyHost';
  static const String port = 'proxyPort';
  static const String user = 'proxyUser';
  static const String pass = 'proxyPass';
  static const String hostPort = 'hostPort';
  static const String url = 'proxyUrl';

  static const List<String> all = [name, type, host, port, user, pass, hostPort, url];

  /// 组合字段会展开成多个基础字段，占用一个粘贴分段
  static bool isComposite(String field) => field == hostPort || field == url;

  static String display(String field) {
    switch (field) {
      case name:
        return '名称';
      case type:
        return '类型';
      case host:
        return '地址';
      case port:
        return '端口';
      case user:
        return '用户名';
      case pass:
        return '密码';
      case hostPort:
        return '地址:端口';
      case url:
        return '完整 URL';
      default:
        return field;
    }
  }
}

/// 一条可复用的粘贴识别规则：用什么分隔、各段依次对应哪些字段。
class ProxyPasteProfile {
  final String id;
  final String name;

  /// 分隔符（字面量，支持多字符；空 = 整段作为一段）
  final String separator;

  /// 分段到字段的映射顺序
  final List<String> fields;

  const ProxyPasteProfile({
    required this.id,
    required this.name,
    required this.separator,
    required this.fields,
  });

  ProxyPasteProfile copyWith({String? name, String? separator, List<String>? fields}) {
    return ProxyPasteProfile(
      id: id,
      name: name ?? this.name,
      separator: separator ?? this.separator,
      fields: fields ?? List<String>.from(this.fields),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'separator': separator,
        'fields': fields,
      };

  static ProxyPasteProfile? fromJson(dynamic value) {
    if (value is! Map) return null;
    final id = (value['id'] ?? '').toString();
    final name = (value['name'] ?? '').toString();
    final separator = (value['separator'] ?? '').toString();
    final rawFields = value['fields'];
    if (id.isEmpty || name.trim().isEmpty || rawFields is! List) return null;
    final fields = rawFields
        .map((e) => e.toString().trim())
        .where((e) => PasteField.all.contains(e))
        .toList();
    if (fields.isEmpty) return null;
    return ProxyPasteProfile(
      id: id,
      name: name,
      separator: separator,
      fields: fields,
    );
  }

  /// 规则摘要，例如 `@ → 名称/类型/地址/端口/用户名/密码`
  String get summary =>
      '${separator.isEmpty ? "整段" : separator} → ${fields.map(PasteField.display).join("/")}';

  /// 解析一段粘贴内容，返回字段值（未提供的字段不会出现在结果里）。
  ///
  /// 规则：
  ///  - 非空分隔符：只取第一行非空内容，按分隔符字面量切分，段数必须与字段数一致；
  ///  - 空分隔符：整段内容作为一段（适合 URL 识别）。
  ///  - 各段会 trim；空段保留（用于“可选用户名/密码”留空的场景）。
  ///
  /// 格式不合法时抛 [FormatException]，消息可直接展示给用户。
  Map<String, String> parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('粘贴内容为空');
    }
    if (separator.isNotEmpty && text.contains(RegExp(r'\r?\n'))) {
      final firstLine = text
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      text = firstLine;
    }
    if (text.isEmpty) {
      throw const FormatException('粘贴内容为空');
    }

    final parts = separator.isEmpty ? <String>[text] : text.split(separator);
    if (parts.length != fields.length) {
      final expected = fields.map(PasteField.display).join('/');
      throw FormatException('字段数量不匹配：规则需要 ${fields.length} 段（$expected），实际 ${parts.length} 段');
    }

    final out = <String, String>{};
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final value = parts[i].trim();
      switch (field) {
        case PasteField.hostPort:
          final split = splitHostPort(value);
          if (split == null) {
            throw FormatException('第 ${i + 1} 段不是「地址:端口」格式：$value');
          }
          out[PasteField.host] = split.$1;
          out[PasteField.port] = split.$2;
          break;
        case PasteField.url:
          final parsed = parseProxyUrl(value);
          if (parsed == null) {
            throw FormatException('第 ${i + 1} 段不是合法的代理 URL：$value');
          }
          out.addAll(parsed);
          break;
        case PasteField.type:
          out[field] = _normalizeType(value);
          break;
        default:
          out[field] = value;
      }
    }
    return out;
  }

  static String _normalizeType(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'socks' || v == 'socks5' || v == 'socksv5') return 'socks5';
    if (v == 'http' || v == 'https') return 'http';
    return raw.trim();
  }

  /// 拆分 `host:port` / `[IPv6]:port`；没有端口或格式错误返回 null
  static (String, String)? splitHostPort(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end <= 1 || end + 1 >= s.length || s[end + 1] != ':') return null;
      final host = s.substring(0, end + 1);
      final port = s.substring(end + 2).trim();
      return port.isEmpty ? null : (host, port);
    }
    final idx = s.lastIndexOf(':');
    if (idx <= 0 || idx >= s.length - 1) return null;
    final host = s.substring(0, idx).trim();
    final port = s.substring(idx + 1).trim();
    if (host.isEmpty || port.isEmpty) return null;
    return (host, port);
  }

  /// 解析代理 URL；无法识别 scheme/主机时返回 null
  static Map<String, String>? parseProxyUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'socks5://$text');
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    final type = (scheme == 'socks' || scheme == 'socks5') ? 'socks5' : 'http';
    final out = <String, String>{
      PasteField.type: type,
      PasteField.host: uri.host,
    };
    if (uri.hasPort) out[PasteField.port] = uri.port.toString();
    if (uri.userInfo.isNotEmpty) {
      final idx = uri.userInfo.indexOf(':');
      if (idx >= 0) {
        out[PasteField.user] = Uri.decodeComponent(uri.userInfo.substring(0, idx));
        out[PasteField.pass] = Uri.decodeComponent(uri.userInfo.substring(idx + 1));
      } else {
        out[PasteField.user] = Uri.decodeComponent(uri.userInfo);
      }
    }
    return out;
  }
}

/// 粘贴识别规则的持久化（SharedPreferences）。
///
/// 首次使用时写入三套默认规则（@ / # / |）；用户删空后不会再次自动生成。
class ProxyPasteProfiles {
  static const String _profilesKey = 'proxyPasteProfiles';
  static const String _lastProfileKey = 'proxyPasteLastProfile';

  static List<ProxyPasteProfile> defaults() {
    const fields = [
      PasteField.name,
      PasteField.type,
      PasteField.host,
      PasteField.port,
      PasteField.user,
      PasteField.pass,
    ];
    return [
      const ProxyPasteProfile(
        id: 'builtin_at',
        name: '识别配置1',
        separator: '@',
        fields: fields,
      ),
      const ProxyPasteProfile(
        id: 'builtin_hash',
        name: '识别配置2',
        separator: '#',
        fields: fields,
      ),
      const ProxyPasteProfile(
        id: 'builtin_pipe',
        name: '识别配置3',
        separator: '|',
        fields: fields,
      ),
      const ProxyPasteProfile(
        id: 'builtin_url',
        name: '识别配置4（完整URL）',
        separator: '',
        fields: [PasteField.url],
      ),
    ];
  }

  static Future<List<ProxyPasteProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null) {
      final seed = defaults();
      await prefs.setString(
          _profilesKey, jsonEncode(seed.map((e) => e.toJson()).toList()));
      return seed;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(ProxyPasteProfile.fromJson)
          .whereType<ProxyPasteProfile>()
          .toList();
    } catch (e) {
      debugPrint('ProxyPasteProfiles.load: $e');
      return [];
    }
  }

  static Future<void> save(List<ProxyPasteProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _profilesKey, jsonEncode(profiles.map((e) => e.toJson()).toList()));
  }

  static Future<String> lastProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastProfileKey) ?? '';
  }

  static Future<void> setLastProfileId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastProfileKey, id);
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
