import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppUpdate extends StatefulWidget {
  AppUpdate(
      {super.key,
      required this.version,
      required this.versionName,
      required this.modifyContent,
      required this.downloadUrl});

  String version;
  String versionName;
  String modifyContent;
  String downloadUrl;

  @override
  State<AppUpdate> createState() => _AppUpdateState();
}

class _AppUpdateState extends State<AppUpdate> {
  int retryCount = 0;
  int maxRetry = 2; // 最大重试次数
  static const platform = MethodChannel('cn.ys1231/appproxy/appupdate');
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: const Text('更新提示'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Text('当前版本:${widget.version}')),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('最新版本:${widget.versionName}')),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('更新内容:${widget.modifyContent}',overflow: TextOverflow.ellipsis,maxLines: 10,)),
          ]
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('download url: ${widget.downloadUrl}');
              platform.invokeMethod("startDownload", widget.downloadUrl);
              Navigator.of(context).pop();
            },
            child: const Text('下载'),
          ),
        ]);
  }

  @override
  void initState() {
    super.initState();
  }
}
