import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 10.0, top: 10.0),
          child: const Text('关于', style: TextStyle(color: Colors.lightBlue)),
        ),
        const SizedBox(height: 10.0),
        GestureDetector(
          child: Card(
              child: Container(
            padding: const EdgeInsets.only(left: 10.0),
            width: MediaQuery.of(context).size.width,
            height: 50.0,
            child: const Center(child: Text('关于 appproxy')),
          )),
          onTap: () {
            // 显示当前app的信息
            showAboutDialog(
              context: context,
              applicationName: 'appproxy',
              applicationVersion: '0.0.1',
              applicationIcon: const Icon(Icons.app_registration),
              applicationLegalese: 'Copyright © 2024',
              children: [
                const Text('appproxy 是一个轻量级的VPN代理工具，支持HTTP, SOCKS5协议'),
                const Text('作者：@iyue'),
                const Text('更新时间：2024-06-02'),
                Row(
                  children: [
                    const Text('github:'),
                    TextButton(
                        onPressed: () {
                          _launchUrl('https://github.com/ys1231/appproxy');
                        },
                        child: const Text('appproxy')),
                  ],
                ),
              ],
            );
          },
        )
      ],
    );
  }
}

Future<void> _launchUrl(_url) async {
  if (!await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication)) {
    throw Exception('Could not launch $_url');
  }
}
