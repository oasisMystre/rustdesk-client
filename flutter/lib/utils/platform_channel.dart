import 'package:flutter/services.dart';

enum PermissionAuthorizeType {
  undetermined,
  authorized,
  denied,
}

class RdPlatformChannel {
  RdPlatformChannel._();

  static RdPlatformChannel get instance => RdPlatformChannel._();

  final MethodChannel _hostMethodChannel =
      MethodChannel("org.rustdesk.rustdesk/host");

  Future<void> invokeMethod(String method) async {
    return await _hostMethodChannel.invokeMethod(method);
  }

  Future<PermissionAuthorizeType> osxCanRecordAudio() async {
    int response = await _hostMethodChannel.invokeMethod("canRecordAudio");
    switch (response) {
      case > 0:
        return PermissionAuthorizeType.authorized;
      case 0:
        return PermissionAuthorizeType.undetermined;
      default:
        return PermissionAuthorizeType.denied;
    }
  }

  Future<bool> osxRequestAudio() async {
    return await _hostMethodChannel.invokeMethod("requestRecordAudio");
  }
}
