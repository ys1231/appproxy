import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一条被勾选的“应用实例”（同一包名在不同 Android 用户/分身下 UID 不同）。
class AppProxyEntry {
  final int uid;
  final int userId;
  final String packageName;
  final bool multiUser;

  const AppProxyEntry({
    required this.uid,
    required this.userId,
    required this.packageName,
    required this.multiUser,
  });
}

/// 当前勾选的应用集合。
///
/// 代理引擎按 UID 精确定位（eBPF `include_uid`），因此可以只代理主应用
/// （用户 0）或只代理分身（如用户 999），不再按包名一刀切。
/// VPN(tun2socks) 只能作用于当前用户，分身选择由启动流程拦截提示。
class AppProxySelection {
  Map<int, AppProxyEntry> _entries = {};

  /// 是否已经从应用列表拿到了完整元数据（包名/用户）。
  /// 启动时只从本地勾选表拿到 UID 时该值为 false，避免 VPN 用空包名启动。
  bool metadataReady = false;

  /// 应用列表尚未加载时，先用已保存的 UID 填充（eBPF 可用；VPN 会等待）
  void replaceUids(Iterable<int> uids) {
    _entries = {
      for (final uid in uids)
        if (uid > 0)
          uid: AppProxyEntry(
            uid: uid,
            userId: 0,
            packageName: '',
            multiUser: false,
          ),
    };
    metadataReady = false;
  }

  /// [metadataReady] 为 false 表示有选中 UID 在当前列表里找不到元数据
  /// （例如重启后还没扫描分身）；此时 eBPF 仍可按 UID 工作，VPN 需要先扫描。
  void replaceAll(Iterable<AppProxyEntry> entries, {bool metadataReady = true}) {
    _entries = {for (final e in entries) e.uid: e};
    this.metadataReady = metadataReady;
  }

  void setSelected(AppProxyEntry entry, bool selected) {
    if (selected) {
      _entries[entry.uid] = entry;
    } else {
      _entries.remove(entry.uid);
    }
  }

  void clear() {
    _entries = {};
    metadataReady = true;
  }

  bool containsUid(int uid) => _entries.containsKey(uid);

  List<AppProxyEntry> get entries => _entries.values.toList();

  List<int> get uids => _entries.keys.toList();

  Set<String> get packages =>
      _entries.values
          .map((e) => e.packageName)
          .where((e) => e.isNotEmpty)
          .toSet();

  /// VPN 能代理的包：仅当前用户（含未标记为 multiUser 的条目）
  List<String> get currentUserPackages =>
      _entries.values
          .where((e) => !e.multiUser && e.packageName.isNotEmpty)
          .map((e) => e.packageName)
          .toSet()
          .toList();

  bool get hasNonCurrentUser => _entries.values.any((e) => e.multiUser);

  bool get hasCurrentUser => _entries.values.any((e) => !e.multiUser);

  /// 原生 VPN 通道参数（只包含当前用户包名）
  String getListString() => jsonEncode(currentUserPackages);

  String debugSummary() =>
      'uids=${_entries.keys.toList()} metadataReady=$metadataReady';
}

AppProxySelection appProxySelection = AppProxySelection();
