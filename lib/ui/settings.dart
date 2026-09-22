import 'dart:convert';

import 'package:appproxy/data/common.dart';
import 'package:appproxy/events/theme/theme_bloc.dart';
import 'package:appproxy/ui/app_update.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:version/version.dart';
import 'package:file_picker/file_picker.dart';
import '../data/proxy_config_data.dart';
import '../events/language/language_bloc.dart';
import '../events/restore/restore_cubit.dart';
import '../generated/l10n.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  static const platform = MethodChannel('cn.ys1231/appproxy/mcpserver');
  var _version = "v0";
  String _arch = "";
  bool _isSwitchZh = true;
  bool _isEnableDarkMode = false;
  bool _isMcpServer = false;
  bool _isCheckUpdate = true;
  bool _isCheckWifi = true;
  final portController = TextEditingController();
  final passController = TextEditingController();
  var mcpPort = 0;
  var authToken = "";
  late var sMsg;
  final ProxyConfigData _proxyConfigData = ProxyConfigData();

  void initDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    _arch = androidInfo.supportedAbis[0];
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    // 初始化设置数据
    _isSwitchZh = await AppSetings.getCnOrEn();
    _isEnableDarkMode = await AppSetings.getEnableDarkMode();
    _isCheckUpdate = await AppSetings.getCheckUpdate();
    _isCheckWifi = await AppSetings.getCheckWifi();
    _isMcpServer = await AppSetings.getMcpServer();
    mcpPort = await AppSetings.getMcpPort();
    authToken = await AppSetings.getAuthToken();
    platform.invokeMethod('updateMcpServerConfig', [mcpPort, authToken]);
    if (_isMcpServer) {
      platform.invokeMethod('startMcpServer');
    }
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
    if (_isEnableDarkMode) {
      context.read<ThemeBloc>().add(SetThemeEvent(ThemeMode.dark));
    }
    sMsg = ScaffoldMessenger.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(S.current.text_settings),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10.0, top: 10.0),
              child:
                  Text(S.of(context).text_theme, style: const TextStyle(color: Colors.lightBlue)),
            ),
            GestureDetector(
              child: Card(
                  child: Container(
                      padding: const EdgeInsets.only(left: 10.0),
                      width: MediaQuery.of(context).size.width,
                      height: 50.0,
                      child: Row(children: [
                        Align(
                            alignment: Alignment.centerLeft,
                            child: Text(S.of(context).text_is_dark_mode)),
                        const Spacer(),
                        Switch(
                            value: _isEnableDarkMode,
                            onChanged: (bool newValue) {
                              setState(() {
                                _isEnableDarkMode = newValue;
                                debugPrint('isEnableDarkMode:$newValue');
                                AppSetings.setEnableDarkMode(newValue);
                                if (_isEnableDarkMode) {
                                  context.read<ThemeBloc>().add(SetThemeEvent(ThemeMode.dark));
                                } else {
                                  context.read<ThemeBloc>().add(SetThemeEvent(ThemeMode.light));
                                }
                              });
                            })
                      ]))),
              onTap: () {
                // 切换主题
                setState(() {
                  _isEnableDarkMode = !_isEnableDarkMode;
                  debugPrint('isEnableDarkMode:$_isEnableDarkMode');
                  AppSetings.setEnableDarkMode(_isEnableDarkMode);
                  if (_isEnableDarkMode) {
                    context.read<ThemeBloc>().add(SetThemeEvent(ThemeMode.dark));
                  } else {
                    context.read<ThemeBloc>().add(SetThemeEvent(ThemeMode.light));
                  }
                });
              },
            ),
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10.0, top: 10.0),
              child: Text(S.of(context).LanguageChoice,
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
                      Align(alignment: Alignment.centerLeft, child: Text(S.of(context).text_cn_en)),
                      const Spacer(),
                      Switch(
                          value: _isSwitchZh,
                          onChanged: (bool newValue) {
                            _isSwitchZh = newValue;
                            AppSetings.setCnOrEn(newValue);
                            if (newValue) {
                              context
                                  .read<LanguageBloc>()
                                  .add(SetLanguageEvent(const Locale('zh', 'CN')));
                            } else {
                              context
                                  .read<LanguageBloc>()
                                  .add(SetLanguageEvent(const Locale('en', 'US')));
                            }
                          })
                    ],
                  ),
                ),
              ),
              onTap: () {
                setState(() {
                  _isSwitchZh = !_isSwitchZh;
                  if (_isSwitchZh) {
                    context.read<LanguageBloc>().add(SetLanguageEvent(const Locale('zh', 'CN')));
                  } else {
                    context.read<LanguageBloc>().add(SetLanguageEvent(const Locale('en', 'US')));
                  }
                  debugPrint('isSwitchZh:$_isSwitchZh');
                });
              },
            ),
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10.0, top: 10.0),
              child: const Text("MCP 服务", style: TextStyle(color: Colors.lightBlue)),
            ),
            GestureDetector(
              child: Card(
                  child: Container(
                padding: const EdgeInsets.only(left: 10.0),
                width: MediaQuery.of(context).size.width,
                height: 50.0,
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              Text(S.of(context).mcp_switch_text, overflow: TextOverflow.ellipsis)),
                    ),
                    Switch(
                        value: _isMcpServer,
                        onChanged: (bool newValue) {
                          setState(() {
                            _isMcpServer = newValue;
                            AppSetings.setMcpServer(newValue);
                            if (newValue) {
                              platform.invokeMethod('startMcpServer');
                            } else {
                              platform.invokeMethod('stopMcpServer');
                            }
                          });
                          debugPrint(S.of(context).mcp_server);
                        })
                  ],
                ),
              )),
              // 支持等待异步弹框
              onTap: () async {
                if (!_isMcpServer) return;
                portController.text = mcpPort.toString();
                passController.text = authToken;
                await showDialog(
                    context: context,
                    builder: (context) {
                      bool isObscure = true;
                      return AlertDialog(
                        title: const Text('MCP Server'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8.0,
                          children: [
                            TextField(
                              controller: portController,
                              decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: S.of(context).mcp_port),
                            ),
                            TextField(
                                controller: passController,
                                obscureText: isObscure,
                                obscuringCharacter: "*",
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: S.of(context).mcp_auth,
                                )),
                          ],
                        ),
                        actions: [
                          Center(
                            child: TextButton(
                                onPressed: () {
                                  var port = int.parse(portController.text);
                                  var auth = passController.text;
                                  debugPrint(
                                      'update MCP PORT:${portController.text} AUTH:${passController.text}');
                                  if (mcpPort != port || authToken != auth) {
                                    setState(() {
                                      mcpPort = port;
                                      authToken = auth;
                                      AppSetings.setMcpPort(port);
                                      AppSetings.setAuthToken(auth);
                                      platform.invokeMethod('updateMcpServerConfig', [port, auth]);
                                      sMsg.showSnackBar(SnackBar(
                                          content: Text('MCP PORT: $mcpPort AUTH: $authToken'),
                                          backgroundColor: Colors.greenAccent));
                                    });
                                  }
                                  Navigator.of(context).pop();
                                },
                                child:
                                    Text(S.of(context).ok, style: const TextStyle(fontSize: 16.0))),
                          )
                        ],
                      );
                    });
              },
            ),
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
                            debugPrint('${S.of(context).text_check_update}:$newValue');
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
              child: Text(S.of(context).text_wifi_check,
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
                          child: Text(S.of(context).text_is_check_wifi)),
                      const Spacer(),
                      Switch(
                          value: _isCheckWifi,
                          onChanged: (bool newValue) {
                            debugPrint(S.of(context).text_wifi_check);
                            setState(() {
                              _isCheckWifi = newValue;
                              AppSetings.setCheckWifi(newValue);
                            });
                          })
                    ],
                  ),
                ),
              ),
              onTap: () {
                // 切换wifi检查
                setState(() {
                  _isCheckWifi = !_isCheckWifi;
                  debugPrint('isCheckWifi:$_isCheckWifi');
                  AppSetings.setCheckWifi(_isCheckWifi);
                });
              },
            ),
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10.0, top: 10.0),
              child: Text(S.of(context).text_backuprestore, style: const TextStyle(color: Colors.lightBlue)),
            ),
            Card(
              child: Container(
                padding: const EdgeInsets.only(left: 10.0),
                // 去掉左侧内边距，让两个按钮可以等分整个卡片宽度，
                // 避免按钮整体偏向一侧导致视觉不协调
                width: MediaQuery.of(context).size.width,
                height: 50.0,
                child: Row(
                  children: [
                    Align(alignment: Alignment.centerLeft, child: Text(S.of(context).overwrite_existing_config)),
                    // Expanded 让"备份"按钮占据剩余宽度的一半，
                    // 图标与文字在按钮内水平居中，与设置列表风格保持一致
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          // TextButton 文字/图标默认使用主题 primary 紫色，
                          // 这里改为正文颜色，与上方普通 Text 设置项保持一致
                          // foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        // 使用 outlined 风格图标，视觉上更轻量、更符合设置项样式
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(S.of(context).text_backup),
                        onPressed: () async {
                          // debugPrint("---- 备份------");
                          var fileName =
                              'appproxy_backup_${DateTime.now().millisecondsSinceEpoch}.json';
                          final bytes = await _proxyConfigData.toBytes();
                          if (bytes.isNotEmpty) {
                            final path = FilePicker.saveFile(fileName: fileName, bytes: bytes);
                            debugPrint("备份文件路径: $path");
                          }else{
                            debugPrint("备份失败, 配置文件为空");
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(S.of(context).backup_failed)));
                          }
                        },
                      ),
                    ),
                    // 竖分隔线用于区分"备份/还原"两个独立操作，
                    // indent/endIndent 控制分隔线上下留白，避免顶到卡片边缘
                    const VerticalDivider(width: 1, indent: 12, endIndent: 12),
                    // Expanded 让"还原"按钮占据剩余宽度的一半，与左侧按钮对称
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          // 同样改为正文颜色，保证"备份/还原"两侧颜色一致
                          // foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        icon: const Icon(Icons.restore_outlined),
                        label: Text(S.of(context).text_restore),
                        onPressed: () async {
                          PlatformFile? file = await FilePicker.pickFile(
                              type: FileType.custom,
                              allowedExtensions: ['json']);
                          if (file != null) {
                            // 还原配置文件
                            var state = await _proxyConfigData.fromBytes(await file.readAsBytes());
                            if (state) {
                              if (!mounted) return;
                              context.read<RestoreCubit>().increment();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(S.of(context).restore_success)));
                            } else {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(S.of(context).restore_failed)));
                            }
                          } else {
                            debugPrint("还原失败, 未选择文件");
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 10.0, top: 10.0),
              child:
                  Text(S.of(context).text_about, style: const TextStyle(color: Colors.lightBlue)),
            ),
            GestureDetector(
              child: Card(
                  child: Container(
                padding: const EdgeInsets.only(left: 10.0),
                width: MediaQuery.of(context).size.width,
                height: 50.0,
                child: Center(child: Text('${S.current.text_about} appproxy')),
              )),
              onTap: () {
                const String buildDate =
                    String.fromEnvironment('BUILD_DATE', defaultValue: 'unknown');
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
                    Text('${S.of(context).text_update_time}：$buildDate'),
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
  String appproxyUpdateUrl =
      url != "" ? url : "https://pfile.ys1231.cn/modules/appproxy/appproxy.json";
  // 使用dio获取版本信息
  String versionName = "0";
  String modifyContent = "";
  String DownloadUrl = "";
  try {
    var dio = Dio();
    Response value = await dio.get(appproxyUpdateUrl);
    if (appproxyUpdateUrl.contains('ys1231.cn')) {
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
      appproxyUpdateUrl = "https://api.github.com/repos/ys1231/appproxy/releases/latest";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).text_get_version_info_fail)));
      showUpdateDialog(context, version, arch, url: appproxyUpdateUrl, retryCount: retryCount);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).text_get_version_info_check_networ)));
      return;
    }
  }

  Version ver1 = Version.parse(versionName.replaceAll('v', ''));
  Version ver2 = Version.parse(version.replaceAll('v', ''));
  if (ver1 <= ver2 || versionName == "0") {
    if (versionName == "0") {
      return;
    }
    debugPrint('${S.of(context).text_current_latest},current:$version,new:$versionName');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.of(context).text_current_latest)));
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
