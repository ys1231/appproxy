import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// 「配置 + sing-box 二进制」一体化备份包（ZIP）。
///
/// 目录结构：
///   manifest.json       格式版本、ABI、二进制来源版本等
///   proxyConfig.json    代理配置（与原 JSON 备份相同的数组格式）
///   sing-box-<abi>      可选二进制
///
/// 兼容策略：只有配置时仍生成原来的纯 JSON；选择包含二进制时才生成 ZIP。
/// 还原时通过文件头自动识别，老备份文件继续可还原。
class ProxyBackupBundle {
  static const String manifestName = 'manifest.json';
  static const String configName = 'proxyConfig.json';

  final Uint8List configBytes;
  final Uint8List? binaryBytes;
  final String binaryFileName;
  final Map<String, dynamic> manifest;

  const ProxyBackupBundle({
    required this.configBytes,
    required this.binaryBytes,
    required this.binaryFileName,
    required this.manifest,
  });

  /// ZIP 文件头 PK\x03\x04
  static bool isZip(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  /// 打包；二进制为可选
  static Uint8List encode({
    required Uint8List configBytes,
    Uint8List? binaryBytes,
    required Map<String, dynamic> manifest,
  }) {
    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
        ArchiveFile(manifestName, manifestBytes.length, manifestBytes));
    archive.addFile(ArchiveFile(configName, configBytes.length, configBytes));
    if (binaryBytes != null) {
      final name = _binaryFileNameOf(manifest);
      if (name.isEmpty) {
        throw const FormatException('manifest 缺少 binary.fileName');
      }
      // 二进制本身已压缩过，直接 store，避免无谓的 deflate CPU 开销
      final binaryFile = ArchiveFile(name, binaryBytes.length, binaryBytes);
      binaryFile.compression = CompressionType.none;
      archive.addFile(binaryFile);
    }
    final zipped = ZipEncoder().encodeBytes(archive);
    if (zipped.isEmpty) {
      throw const FormatException('打包备份失败');
    }
    return zipped;
  }

  /// 解析 ZIP；不是有效备份时返回 null
  static ProxyBackupBundle? decode(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final configFile = archive.findFile(configName);
      if (configFile == null) return null;
      final manifestFile = archive.findFile(manifestName);
      var manifest = <String, dynamic>{};
      if (manifestFile != null) {
        final decoded = jsonDecode(utf8.decode(manifestFile.content));
        if (decoded is Map) manifest = Map<String, dynamic>.from(decoded);
      }
      Uint8List? binary;
      final name = _binaryFileNameOf(manifest);
      if (name.isNotEmpty) {
        final binaryFile = archive.findFile(name);
        if (binaryFile != null) binary = binaryFile.content;
      }
      return ProxyBackupBundle(
        configBytes: configFile.content,
        binaryBytes: binary,
        binaryFileName: name,
        manifest: manifest,
      );
    } catch (e) {
      debugPrint('ProxyBackupBundle.decode: $e');
      return null;
    }
  }

  /// 从 manifest 读取二进制文件名（不带路径，防止恶意压缩包路径穿越）
  static String _binaryFileNameOf(Map<String, dynamic> manifest) {
    final info = manifest['binary'];
    if (info is! Map) return '';
    final name = (info['fileName'] ?? '').toString().trim();
    if (name.isEmpty || name.contains('/') || name.contains('\\')) return '';
    return name;
  }
}
