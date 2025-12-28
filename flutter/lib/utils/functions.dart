import 'dart:async';

Timer periodicImmediate(
    Duration duration, Future<void> Function(Timer? timer) callback) {
  Future.delayed(Duration.zero, () => callback(null));
  return Timer.periodic(duration, (timer) async {
    await callback(timer);
  });
}
