import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppConfigList extends StatefulWidget {
  const AppConfigList({super.key, required this.onTitleChange});

  final Function(String) onTitleChange;

  @override
  State<AppConfigList> createState() => _AppConfigState();
}

class _AppConfigState extends State<AppConfigList> {
  var _itemCount = 0;
  late List _jsonAppListInfo;
  static const platform = MethodChannel('cn.ys1231/appproxy');
  final Map<String, bool> _selectedItemsMap = {};
  late Future<bool> _calculation;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print("iyue-> initState");
    }
    _calculation = getAppList();
  }

  Future<bool> getAppList() async {
    try {
      if (kDebugMode) {
        print("iyue-> getAppList");
      }
      final appList = await platform.invokeMethod('getAppList');
      _jsonAppListInfo = jsonDecode(appList);
      print("iyue-<getAppList> _itemCount:$_itemCount");
      setState(() {
        _itemCount = _jsonAppListInfo.length;
      });
      return true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Failed to get app list: '${e.message}'.");
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('An unexpected error happened: $e');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      //   在当前帧构建完成后，调用onTitleChange
      widget.onTitleChange('AppConfigList');
    });
    if (kDebugMode) {
      print("iyue-<build> _itemCount:$_itemCount");
    }

    return FutureBuilder(
        future: _calculation,
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          } else {
            return RefreshIndicator(
              onRefresh: () {
                return Future.delayed(const Duration(seconds: 1), () {
                  getAppList();
                  setState(() {});
                  if (kDebugMode) {
                    print("onRefresh");
                  }
                });
              },
              child: Scrollbar(
                child: ListView.separated(
                  // 返回一个零尺寸的SizedBox
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox.shrink(),
                  itemCount: _itemCount,
                  itemBuilder: (BuildContext context, int index) {
                    return Card(
                      key: ValueKey(index),
                      child: ListTile(
                        horizontalTitleGap: 20,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0.0, horizontal: 16.0),
                        leading: SizedBox(
                          width: 38, // 设置宽度
                          height: 38, // 设置高度
                          child: Image.memory(
                            base64Decode(_jsonAppListInfo[index]["iconBytes"]),
                            fit: BoxFit.cover, // 保持图片的宽高比
                          ),
                        ),
                        // leading: const ImageIcon(),
                        title: Text(_jsonAppListInfo[index]["label"]),
                        subtitle: Text(_jsonAppListInfo[index]["packageName"]),
                        trailing: CardCheckbox(
                            isSelected: _selectedItemsMap[_jsonAppListInfo[index]["packageName"]] ?? false,
                            index: index,
                            callbackOnChanged: (newValue) {
                              _selectedItemsMap[_jsonAppListInfo[index]["packageName"]] = newValue;
                            }),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        });
  }
}

class CardCheckbox extends StatefulWidget {
  CardCheckbox(
      {super.key,
      required bool isSelected,
      required this.index,
      required this.callbackOnChanged})
      : _isSelected = isSelected;
  Function(bool) callbackOnChanged;
  bool _isSelected = false;
  int index = 0;

  @override
  State<StatefulWidget> createState() => _CardCheckboxState();
}

class _CardCheckboxState extends State<CardCheckbox> {
  void toggleCheckbox() {
    setState(() {
      widget._isSelected = !widget._isSelected;
      widget.callbackOnChanged(widget._isSelected);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: widget._isSelected,
      onChanged: (bool? newValue) {
        widget.callbackOnChanged(newValue!);
        setState(() {
          widget._isSelected = newValue;
        });
        // 如果需要，这里可以处理选中项的变化逻辑
        if (kDebugMode) {
          print("index:$widget.index,newValue:$newValue");
        }
      },
    );
  }
}
