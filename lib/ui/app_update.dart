import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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

  static const platform = MethodChannel('cn.ys1231/appproxy/appupdate');

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.8; // 设置为屏幕宽度的80%
    final maxHeight = MediaQuery.of(context).size.height * 0.3; // 设置为屏幕高度的80%
    return AlertDialog(
        title: const Text('更新提示'),
        content: Column(
            mainAxisSize: MainAxisSize.min, // 仅占用必要高度
            crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('当前版本:${widget.version}')),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('最新版本:${widget.versionName}')),
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('更新内容:',overflow: TextOverflow.ellipsis,maxLines: 10,)),
                  // child: Text('更新内容:${widget.modifyContent}',overflow: TextOverflow.ellipsis,maxLines: 10,)),
              const SizedBox(height: 4,),
              SizedBox(
                  width: maxWidth,
                  height: maxHeight,
                  child: Markdown(
                      padding: const EdgeInsets.all(0.0),
                      selectable: true,
                      data: widget.modifyContent,
                      extensionSet: md.ExtensionSet(
                      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                      <md.InlineSyntax>[
                        md.EmojiSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
                      ],
                    ),
                  )
              ),
          ]
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                child: const Text('取消',textAlign: TextAlign.end,),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              SizedBox(width: maxWidth*0.2,),
              TextButton(
                child: const Text('下载',textAlign: TextAlign.end,),
                onPressed: () {
                  debugPrint('download url: ${widget.downloadUrl}');
                  platform.invokeMethod("startDownload", widget.downloadUrl);
                  Navigator.of(context).pop();
                },
              ),
            ],
          )

        ]);
  }

}
