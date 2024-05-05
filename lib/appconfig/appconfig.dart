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
  final _itemCount = 100;
  late List<bool> _selectedItems;

  static const platform = MethodChannel('samples.flutter.dev/battery');

  @override
  void initState() {
    super.initState();
    _selectedItems = List.generate(_itemCount, (index) => false);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      //   在当前帧构建完成后，调用onTitleChange
      widget.onTitleChange('AppConfigList');
    });
    return RefreshIndicator(
      onRefresh: () {
        return Future.delayed(const Duration(seconds: 1), () {
          if (kDebugMode) {
            print("onRefresh");
          }
        });
      },
      child: Scrollbar(
        child: ListView.separated(
            itemBuilder: (BuildContext context, int index) {
              return ListTile(
                // contentPadding: const EdgeInsets.only(left: 10.0),
                leading: const Icon(Icons.contact_page_outlined),
                title: Text("Title $index"),
                subtitle: Text("Subtitle $index"),
                trailing: Checkbox(
                  value: _selectedItems[index],
                  onChanged: (bool? newValue) {
                    setState(() {
                      _selectedItems[index] = newValue!;
                    });
                    // 如果需要，这里可以处理选中项的变化逻辑
                    if (kDebugMode) {
                      print("index:$index,newValue:$newValue");
                    }
                  },
                ),
                onTap: () {
                  setState(() {
                    _selectedItems[index] = !_selectedItems[index];
                  });
                  if (kDebugMode) {
                    print("index:$index");
                  }
                },
              );
            },
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(),
            itemCount: _itemCount
        ),
      ),
    );
  }
}
