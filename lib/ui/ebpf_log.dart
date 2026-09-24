import 'package:appproxy/data/ebpf_proxy_data.dart';
import 'package:appproxy/generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// eBPF 运行日志页。
///
/// 日志来自原生的运行目录（root 700），由原生经 su 读取后回传：
///   box.log      —— config.json 里 log.output 的结构化日志（eBPF 启动摘要、连接记录）
///   sing-box.log —— 启动命令的 stdout/stderr（崩溃报错）
class EbpfLogPage extends StatefulWidget {
  const EbpfLogPage({super.key});

  /// 创建 State
  @override
  State<EbpfLogPage> createState() => _EbpfLogPageState();
}

class _EbpfLogPageState extends State<EbpfLogPage> {
  String _log = '';
  bool _loading = true;

  /// 初始化：进页即拉一次日志
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 重新读取日志（经原生以 root 读取运行目录里的日志文件）
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final log = await EbpfProxyData.readLog(maxBytes: 64 * 1024);
      if (!mounted) return;
      setState(() {
        _log = log;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _log = '$e';
        _loading = false;
      });
    }
  }

  /// 把当前日志复制到剪贴板
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.of(context).ebpf_copied)));
  }

  /// 构建日志页：正文放在 Card 里，顶部提供复制与刷新
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.ebpf_log_title),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            tooltip: s.ebpf_copy,
            icon: const Icon(Icons.copy),
            onPressed: _log.isEmpty ? null : _copy,
          ),
          IconButton(
            tooltip: s.ebpf_check,
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      // 排版与设置页保持一致：留白 10、内容放在 Card 里
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(10.0),
              child: Card(
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  padding: const EdgeInsets.all(10.0),
                  child: SelectableText(
                    _log.isEmpty ? s.ebpf_log_empty : _log,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.0),
                  ),
                ),
              ),
            ),
    );
  }
}
