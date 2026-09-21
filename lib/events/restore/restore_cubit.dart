import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

class RestoreCubit extends Cubit<int> {
  RestoreCubit() : super(0);
  void increment() => emit(state + 1);
}
