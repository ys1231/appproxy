import 'package:appproxy/data/common.dart';
import 'package:appproxy/data/ebpf_proxy_data.dart';
import 'package:appproxy/generated/l10n.dart';
import 'package:appproxy/ui/ebpf_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// eBPF(sing-box) 透明代理的独立设置页。
///
/// 「设置」页只保留一个入口，具体内容都在这里：
///   检测（状态 + 检测按钮）/ 二进制（版本、下载、续传、更新）/ 数据面 / 高级（下载源、日志、清理）
///
/// 排版刻意与设置页保持一致，避免风格割裂：
///   - 分区标题：`Container(左内边距 10, 上内边距 10) + Text(color: lightBlue)`
///   - 每行独立一张 `Card`，行高统一 50，右侧放值/开关/箭头（可点行加 chevron）
///   - 说明性文字用小号字（11/12/13）但**不用灰字**；只在有语义时才上色（可用=绿、不可用=红、有新版本/失败原因=橙）
///
/// 说明：
///  - 检测结果由原生持久化在 support.json（属「设置侧」数据，不进备份/恢复）
///  - 只有「检测」按钮会跑 root 命令；打开页面只读缓存（秒开）
///  - 二进制缺失时点「检测」会先自动下载再检测
class EbpfSettingsPage extends StatefulWidget {
  const EbpfSettingsPage({super.key});

  /// 创建 State
  @override
  State<EbpfSettingsPage> createState() => _EbpfSettingsPageState();
}

class _EbpfSettingsPageState extends State<EbpfSettingsPage> {
  EbpfSupportStatus _support = const EbpfSupportStatus();
  EbpfBinaryStatus _binary = const EbpfBinaryStatus();
  EbpfBinaryUpdateInfo _updateInfo = const EbpfBinaryUpdateInfo();
  bool _checking = false; // 检测中（按钮 loading）
  bool _downloading = false; // 下载中
  int _percent = 0;
  String _dataPlane = 'cgroup';
  String _downloadBase = '';

  /// 有新版：已知最新版本，且与本地「下载来源版本」不同
  bool get _hasUpdate =>
      _updateInfo.ok &&
      _binary.packageVersion.isNotEmpty &&
      _updateInfo.latestVersion != _binary.packageVersion;

  /// 初始化：读设置（数据面/下载源）+ 读检测缓存 + 静默检查版本；并挂上原生进度回调
  @override
  void initState() {
    super.initState();
    // 原生进度回调：下载百分比（phase=download）
    EbpfProxyData.onProgress = (phase, percent) {
      if (!mounted) return;
      setState(() {
        if (phase == 'download') {
          _downloading = true;
          _percent = percent ?? 0;
        } else {
          _downloading = false;
        }
      });
    };
    _loadAll();
  }

  /// 释放：摘掉进度回调，避免回调打到已销毁的 State
  @override
  void dispose() {
    EbpfProxyData.onProgress = null;
    super.dispose();
  }

  /// 首次加载：设置项 + 缓存状态 + 版本清单（都不执行 root 命令）
  Future<void> _loadAll() async {
    _dataPlane = await AppSetings.getEbpfDataPlane();
    _downloadBase = await AppSetings.getEbpfDownloadBase();
    await _loadCache();
    await _checkUpdate();
  }

  /// 读缓存（不跑 root 命令）
  Future<void> _loadCache() async {
    try {
      final support = await EbpfProxyData.getSupportStatus();
      final binary = await EbpfProxyData.getBinaryStatus();
      if (!mounted) return;
      setState(() {
        _support = support;
        _binary = binary;
      });
    } catch (e) {
      debugPrint("_loadCache: $e");
    }
  }

  /// 静默检查版本清单（{下载源}/update.json）；失败只记录，不打扰用户
  Future<void> _checkUpdate() async {
    try {
      final info = await EbpfProxyData.checkBinaryUpdate();
      if (!mounted) return;
      setState(() => _updateInfo = info);
    } catch (e) {
      debugPrint("_checkUpdate: $e");
    }
  }

  /// 「检测」：唯一会跑 root 命令的入口；二进制缺失时先自动下载
  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final support = await EbpfProxyData.checkEbpfSupport(autoDownload: true);
      final binary = await EbpfProxyData.getBinaryStatus();
      if (!mounted) return;
      setState(() {
        _support = support;
        _binary = binary;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _downloading = false;
        });
      }
    }
  }

  /// 下载或续传二进制；失败时提示并刷新状态（保留进度以便再点继续）
  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _percent = 0;
    });
    try {
      final binary = await EbpfProxyData.downloadBinary();
      if (!mounted) return;
      setState(() => _binary = binary);
      // 下载成功后会记录来源版本，刷新一次版本信息（有新版提示随之消失）
      await _checkUpdate();
    } catch (e) {
      if (mounted) {
        // 中断时保留进度：提示可再次点击续传
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        await _loadCache();
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 自定义下载源（留空 = 官方地址）
  Future<void> _editDownloadBase() async {
    final controller = TextEditingController(text: _downloadBase);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).ebpf_download_base),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: S.of(ctx).ebpf_download_base_hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).text_cancel)),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              AppSetings.setEbpfDownloadBase(value);
              setState(() => _downloadBase = value);
              Navigator.pop(ctx);
            },
            child: Text(S.of(ctx).text_confirm),
          ),
        ],
      ),
    );
  }

  /// 更新说明：应用内弹窗展示（拉 changelog.md 渲染 Markdown），不跳浏览器。
  /// 参考 App 自身的更新弹窗（lib/ui/app_update.dart）的写法。
  Future<void> _showChangelog() async {
    if (_updateInfo.changelogUrl.isEmpty) return;
    await showDialog(
      context: context,
      builder: (ctx) => _EbpfChangelogDialog(
        url: _updateInfo.changelogUrl,
        currentVersion: _binary.packageVersion.isEmpty ? '?' : _binary.packageVersion,
        latestVersion: _updateInfo.latestVersion,
        onUpdate: () {
          Navigator.of(ctx).pop();
          _download();
        },
      ),
    );
  }

  /// 清理运行目录（保留已下载的二进制）
  Future<void> _cleanupRuntimeDir() async {
    final ok = await EbpfProxyData.cleanupRuntimeDir();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? S.of(context).ebpf_cleanup_done : S.of(context).ebpf_state_fail),
    ));
  }

  // ---------------------------------------------------------------- 通用排版

  /// 分区标题（与设置页一致：浅蓝小标题）
  Widget _sectionHeader(String text) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 10.0, top: 10.0),
        child: Text(text, style: const TextStyle(color: Colors.lightBlue)),
      );

  /// 单行卡片：行高 50，与设置页各行一致。可点时右侧显示箭头。
  Widget _rowCard({
    required String label,
    String? value,
    VoidCallback? onTap,
  }) {
    final card = Card(
      child: Container(
        padding: const EdgeInsets.only(left: 10.0, right: 10.0),
        width: MediaQuery.of(context).size.width,
        height: 50.0,
        child: Row(
          children: [
            Text(label),
            // 右侧值：撑满剩余宽度并右对齐，紧贴箭头（否则会停在中间）
            if (value != null)
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.0),
                ),
              )
            else
              const Spacer(),
            if (onTap != null) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
    return onTap == null ? card : GestureDetector(child: card, onTap: onTap);
  }

  /// 状态行：标签 + 可用/不可用
  Widget _statusLine(String label, bool ok, S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.0))),
          Text(
            ok ? s.ebpf_state_ok : s.ebpf_state_fail,
            style: TextStyle(fontSize: 13.0, color: ok ? Colors.green : Colors.redAccent),
          ),
        ],
      ),
    );
  }

  /// 切换数据面（cgroup 默认 / tc 退路），存设置侧
  void _setDataPlane(String plane) {
    setState(() => _dataPlane = plane);
    AppSetings.setEbpfDataPlane(plane);
  }

  /// 下载行文案：下载中百分比 → 继续下载（未下完）→ 下载 → 更新到 vX → 重新下载
  String _downloadLabel(S s) {
    if (!_binary.exists && _binary.pendingBytes > 0) return s.ebpf_resume;
    if (!_binary.exists) return s.ebpf_download;
    if (_hasUpdate) return '${s.ebpf_update_to} ${_updateInfo.latestVersion}';
    return s.ebpf_redownload;
  }

  /// 构建 eBPF 设置页：检测 / 二进制 / 兼容模式 / 高级 四个分区
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.ebpf_section_title),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---------------- 检测 ----------------
            _sectionHeader(s.ebpf_sec_check),
            Card(
              child: Container(
                padding: const EdgeInsets.all(10.0),
                width: MediaQuery.of(context).size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.ebpf_section_desc, style: const TextStyle(fontSize: 12.0)),
                    const SizedBox(height: 8.0),
                    _statusLine(s.ebpf_label_root, _support.root, s),
                    _statusLine(s.ebpf_label_binary, _support.binaryReady, s),
                    _statusLine(s.ebpf_label_cgroup, _support.cgroup, s),
                    _statusLine(s.ebpf_label_tc, _support.tc, s),
                    if (_support.kernelRelease.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text('${s.ebpf_label_kernel}: ${_support.kernelRelease}',
                            style: const TextStyle(fontSize: 11.0)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${s.ebpf_label_checked_at}: '
                        '${_support.checkedTime?.toString().split('.').first ?? s.ebpf_state_unknown}',
                        style: const TextStyle(fontSize: 11.0),
                      ),
                    ),
                    // 失败原因（原生只回传 required 且非 PASS 的项）
                    if (_support.reasons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          _support.reasons.take(3).join('\n'),
                          style: const TextStyle(fontSize: 11.0, color: Colors.orange),
                        ),
                      ),
                    const SizedBox(height: 6.0),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _checking ? null : _check,
                        icon: _checking
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        label: Text(_checking ? s.ebpf_checking : s.ebpf_check),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- 二进制（紧凑：信息行 + 操作行，不拆多行）----------------
            _sectionHeader(s.ebpf_sec_binary),
            Card(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 8.0),
                width: MediaQuery.of(context).size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.ebpf_label_binary}: '
                      '${_binary.exists ? "${_binary.fileName} · ${_binary.sizeText}" : s.ebpf_state_unknown}',
                      style: const TextStyle(fontSize: 12.0),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        _versionLine(s),
                        style: TextStyle(fontSize: 11.0, color: _hasUpdate ? Colors.orange : null),
                      ),
                    ),
                    if (!_binary.exists && _binary.pendingBytes > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '${s.ebpf_pending_prefix} ${_binary.pendingText}',
                          style: const TextStyle(fontSize: 11.0),
                        ),
                      ),
                    Row(
                      children: [
                        // 更新说明：只要版本清单给了 changelog 就显示（不论当前是否已是最新）
                        if (_updateInfo.changelogUrl.isNotEmpty)
                          TextButton(
                            onPressed: _showChangelog,
                            child: Text(s.ebpf_changelog, style: const TextStyle(fontSize: 12.0)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _downloading ? null : _download,
                          child: Text(_downloading
                              ? '${s.ebpf_downloading} $_percent%'
                              : _downloadLabel(s)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- 数据面 ----------------
            _sectionHeader(s.ebpf_sec_plane),
            Card(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0),
                width: MediaQuery.of(context).size.width,
                // 说明文字在上、靠左；两个选项在下面、靠右
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.ebpf_plane_hint,
                        textAlign: TextAlign.left, style: const TextStyle(fontSize: 11.0)),
                    const SizedBox(height: 6.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ChoiceChip(
                          label: Text(s.ebpf_plane_default),
                          selected: _dataPlane == 'cgroup',
                          onSelected: (v) => _setDataPlane('cgroup'),
                        ),
                        const SizedBox(width: 6.0),
                        ChoiceChip(
                          label: Text(s.ebpf_plane_compat),
                          selected: _dataPlane == 'tc',
                          onSelected: (v) => _setDataPlane('tc'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- 高级 ----------------
            _sectionHeader(s.ebpf_sec_advanced),
            _rowCard(
              label: s.ebpf_download_base,
              value: _downloadBase.isEmpty ? s.ebpf_value_default : _downloadBase,
              onTap: _editDownloadBase,
            ),
            _rowCard(
              label: s.ebpf_view_log,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EbpfLogPage()),
                );
              },
            ),
            _rowCard(label: s.ebpf_cleanup_runtime, onTap: _cleanupRuntimeDir),
            const SizedBox(height: 20.0),
          ],
        ),
      ),
    );
  }

  /// 版本行：当前版本（来源包版本）· sing-box 自身版本 · 最新版本
  String _versionLine(S s) {
    final parts = <String>[];
    if (_binary.exists) {
      parts.add('${s.ebpf_current_version}: '
          '${_binary.packageVersion.isEmpty ? "?" : _binary.packageVersion}');
      final singBox = _binary.version.split('\n').first.trim();
      if (singBox.isNotEmpty) parts.add(singBox);
    }
    if (_updateInfo.ok) {
      parts.add('${s.ebpf_latest_version}: ${_updateInfo.latestVersion}'
          '${_hasUpdate ? " (${s.ebpf_update_available})" : ""}');
    } else if (_updateInfo.error.isNotEmpty) {
      parts.add(_updateInfo.error);
    }
    return parts.join(' · ');
  }
}

/// eBPF 二进制「更新说明」弹窗：拉取 changelog 并渲染 Markdown（不跳浏览器）。
/// 版式参考 App 自身的更新弹窗 `lib/ui/app_update.dart`（同款 AlertDialog + Markdown）。
class _EbpfChangelogDialog extends StatefulWidget {
  const _EbpfChangelogDialog({
    required this.url,
    required this.currentVersion,
    required this.latestVersion,
    required this.onUpdate,
  });

  final String url;
  final String currentVersion;
  final String latestVersion;
  final VoidCallback onUpdate;

  /// 创建 State
  @override
  State<_EbpfChangelogDialog> createState() => _EbpfChangelogDialogState();
}

class _EbpfChangelogDialogState extends State<_EbpfChangelogDialog> {
  String _content = '';
  String _error = '';
  bool _loading = true;

  /// 初始化：读设置（数据面/下载源）+ 读检测缓存 + 静默检查版本；并挂上原生进度回调
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// 拉取更新说明（changelog.md）并渲染；失败只在弹窗内显示错误
  Future<void> _fetch() async {
    try {
      final resp = await Dio().get<String>(
        widget.url,
        options: Options(responseType: ResponseType.plain),
      );
      if (!mounted) return;
      setState(() {
        _content = resp.data ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 构建 eBPF 设置页：检测 / 二进制 / 兼容模式 / 高级 四个分区
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final maxWidth = MediaQuery.of(context).size.width * 0.8;
    final maxHeight = MediaQuery.of(context).size.height * 0.4;
    return AlertDialog(
      title: Text(s.ebpf_changelog),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.ebpf_current_version}: ${widget.currentVersion}'),
          Text('${s.ebpf_latest_version}: ${widget.latestVersion}'),
          const SizedBox(height: 4.0),
          SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error.isNotEmpty
                    ? Text(_error, style: const TextStyle(fontSize: 12.0, color: Colors.orange))
                    : Markdown(
                        padding: EdgeInsets.zero,
                        selectable: true,
                        data: _content,
                        extensionSet: md.ExtensionSet(
                          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                          <md.InlineSyntax>[
                            md.EmojiSyntax(),
                            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
                          ],
                        ),
                      )),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: Text(s.text_cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text('${s.ebpf_update_to} ${widget.latestVersion}'),
          onPressed: widget.onUpdate,
        ),
      ],
    );
  }
}
