import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

class RestoreCubit extends Cubit<int> {
  RestoreCubit() : super(0);
  /// 发一个自增信号；监听方（代理列表页）收到后重新加载配置
  void increment() => emit(state + 1);
}
