import 'package:appproxy/data/common.dart';
import 'package:appproxy/ui/app_update.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:version/version.dart';

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
        title: const Text('设置'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Column(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10.0, top: 10.0),
            child:
                const Text('版本更新', style: TextStyle(color: Colors.lightBlue)),
          ),
          GestureDetector(
            child: Card(
              child: Container(
                padding: const EdgeInsets.only(left: 10.0),
                width: MediaQuery.of(context).size.width,
                height: 50.0,
                child: Row(
                  children: [
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('是否开启更新检测')),
                    const Spacer(),
                    Switch(
                        value: _isCheckUpdate,
                        onChanged: (bool newValue) {
                          debugPrint('更新检测:$newValue');
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
                applicationVersion: _version,
                applicationIcon: const Icon(Icons.app_registration),
                applicationLegalese: 'Copyright © 2024 ...',
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('获取版本信息失败,使用国内更新渠道!')));
      showUpdateDialog(context, version, arch,
          url: appproxyUpdateUrl, retryCount: retryCount);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('获取版本信息失败,请检查网络!')));
      return;
    }
  }

  Version ver1 = Version.parse(versionName.replaceAll('v', ''));
  Version ver2 = Version.parse(version.replaceAll('v', ''));
  if (ver1 <= ver2 || versionName == "0") {
    if (versionName == "0") {
      return;
    }
    debugPrint('当前是最新版本,current:$version,new:$versionName');
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('当前是最新版本')));
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
