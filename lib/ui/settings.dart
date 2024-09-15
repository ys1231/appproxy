import 'package:appproxy/data/common.dart';
import 'package:appproxy/ui/app_update.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:version/version.dart';

import '../generated/l10n.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  var _version = "v0";
  String _arch = "";
  bool _isCheckUpdate = true;

  void initDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    _arch = androidInfo.supportedAbis[0];
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    // 获取是否需要检测更新
    _isCheckUpdate = await AppSetings.getCheckUpdate();
    _version = packageInfo.version;
    if (_isCheckUpdate) {
      showUpdateDialog(context, _version, _arch);
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    initDeviceInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.current.text_settings),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Column(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10.0, top: 10.0),
            child: Text(S.of(context).text_version_update,
                style: const TextStyle(color: Colors.lightBlue)),
          ),
          GestureDetector(
            child: Card(
              child: Container(
                padding: const EdgeInsets.only(left: 10.0),
                width: MediaQuery.of(context).size.width,
                height: 50.0,
                child: Row(
                  children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(S.of(context).text_is_open_check_update)),
                    const Spacer(),
                    Switch(
                        value: _isCheckUpdate,
                        onChanged: (bool newValue) {
                          debugPrint(
                              '${S.of(context).text_check_update}:$newValue');
                          setState(() {
                            _isCheckUpdate = newValue;
                            AppSetings.setCheckUpdate(newValue);
                          });
                        })
                  ],
                ),
              ),
            ),
            onTap: () {
              // const AppUpdate();
              if (_isCheckUpdate) {
                // 开启更新检测
                showUpdateDialog(context, _version, _arch);
              }
            },
          ),
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10.0, top: 10.0),
            child: Text(S.of(context).text_about,
                style: const TextStyle(color: Colors.lightBlue)),
          ),
          const SizedBox(height: 10.0),
          GestureDetector(
            child: Card(
                child: Container(
              padding: const EdgeInsets.only(left: 10.0),
              width: MediaQuery.of(context).size.width,
              height: 50.0,
              child: Center(child: Text('${S.current.text_about} appproxy')),
            )),
            onTap: () {
              // 显示当前app的信息
              showAboutDialog(
                context: context,
                applicationName: 'appproxy',
                applicationVersion: _version,
                applicationIcon: const Icon(Icons.app_registration),
                applicationLegalese: 'Copyright © 2024 ...',
                children: [
                  Text(S.of(context).text_describe),
                  Text(S.of(context).text_author),
                  Text('${S.of(context).text_update_time}：2024-09-15'),
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
      ),
    );
  }
}

Future<void> _launchUrl(_url) async {
  if (!await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication)) {
    throw Exception('Could not launch $_url');
  }
}

/**
 * 显示更新对话框
 */
void showUpdateDialog(BuildContext context, String version, String arch,
    {url = '', retryCount = 0}) async {
  int maxRetry = 2; // 最大重试次数
  // 获取版本信息
  String appproxyUpdateUrl = url != ""
      ? url
      : "https://api.github.com/repos/ys1231/appproxy/releases/latest";
  // 使用dio获取版本信息
  String versionName = "0";
  String modifyContent = "";
  String DownloadUrl = "";
  try {
    var dio = Dio();
    Response value = await dio.get(appproxyUpdateUrl);
    if (appproxyUpdateUrl.contains('ys1231.cn:82')) {
      var data = value.data;
      // 1 普通更新 0 不更新
      versionName = data['VersionName'];
      modifyContent = data['ModifyContent'];
      DownloadUrl = '${data['DownloadUrl']}$versionName/app-$arch-release.apk';
    } else {
      final releasesJson = value.data;
      // 获取最新版本的tag名
      versionName = releasesJson['tag_name'];
      releasesJson['assets'].forEach((asset) {
        if (asset['name'].contains(arch)) {
          DownloadUrl = asset['browser_download_url'];
          return;
        }
      });
      modifyContent = releasesJson['body'];
    }
  } catch (e) {
    if (retryCount < maxRetry) {
      retryCount++;
      appproxyUpdateUrl = "https://ys1231.cn:82/modules/appproxy/appproxy.json";
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).text_get_version_info_fail)));
      showUpdateDialog(context, version, arch,
          url: appproxyUpdateUrl, retryCount: retryCount);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.of(context).text_get_version_info_check_networ)));
      return;
    }
  }

  Version ver1 = Version.parse(versionName.replaceAll('v', ''));
  Version ver2 = Version.parse(version.replaceAll('v', ''));
  if (ver1 <= ver2 || versionName == "0") {
    if (versionName == "0") {
      return;
    }
    debugPrint(
        '${S.of(context).text_current_latest},current:$version,new:$versionName');
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).text_current_latest)));
    return;
  }
  // 显示更新对话框
  AppUpdate appUpdate = AppUpdate(
    version: version,
    versionName: versionName,
    modifyContent: modifyContent,
    downloadUrl: DownloadUrl,
  );
  showDialog(
      context: context,
      builder: (context) {
        return appUpdate;
      });
}
