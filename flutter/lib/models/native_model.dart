import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:device_info_plus/device_info_plus.dart';

import './event_handler.dart';

typedef F3 = Pointer<Uint8> Function(Pointer<Utf8>, int);
typedef F3Dart = Pointer<Uint8> Function(Pointer<Utf8>, Int32);

class PlatformFFi extends Event {
  final String _dir = '';
  final String _homeDir = '';
  late RustdeskImpl _ffiBind;
  StreamEventHandler? _eventCallback;

  PlatformFFi._();

  RustdeskImpl get ffiBind => _ffiBind;
  static final PlatformFFi instance = PlatformFFi._();

  Future<PlatformFFi> init(String appType) async {
    late DynamicLibrary dylib;
    if (Platform.isWindows) {
      dylib = DynamicLibrary.open("librustdesk.dll");
    } else {
      dylib = DynamicLibrary.process();
    }

    _ffiBind = RustdeskImpl(dylib);

    if (Platform.isLinux) {
      await _ffiBind.mainStartDbusServer();
    } else if (Platform.isMacOS) {
      await _ffiBind.mainStartIpcUrlServer();
    }

    _startListenEvent(_ffiBind, appType);

    String id = "Na";
    String name = "Flutter";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isMacOS) {
      MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
      name = macOsInfo.computerName;
      id = macOsInfo.systemGUID ?? id;
    }

    await _ffiBind.mainDeviceId(id: id);
    await _ffiBind.mainDeviceName(name: name);
    await _ffiBind.mainSetHomeDir(home: _homeDir);
    await _ffiBind.mainInit(appDir: _dir, customClientConfig: '');

    return this;
  }

  void setEventCallback(StreamEventHandler function) async {
    debugPrint('start me fuck');
    _eventCallback = function;
  }

  void _startListenEvent(RustdeskImpl rustdeskImpl, String appType) {
    var sink = rustdeskImpl.startGlobalEventStream(appType: appType);
    sink.listen((message) {
      () async {
        debugPrint('message=$message');
        try {
          Map<String, dynamic> event = json.decode(message);
          if (!await tryHandle(event)) {
            if (_eventCallback != null) {
              await _eventCallback!(event);
            }
          }
        } catch (error) {
          debugPrint('json.decode fail(): $error');
        }
      }();
    });
  }
}
