import 'dart:async';

import 'package:flutter/cupertino.dart';

class Debounce {
  Duration delay;
  Timer? _timer;

  Debounce(this.delay);

  call(BuildContext context, void Function(BuildContext) callback) {
    _timer?.cancel();
    _timer = Timer(delay, ()=>callback(context));
  }

  dispose() {
    _timer?.cancel();
  }
}
