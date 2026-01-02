import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';

import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/native_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';

final platformFFi = PlatformFFi.instance;
final platformChannel = RdPlatformChannel.instance;

RustdeskImpl get bind => platformFFi.ffiBind;

late FFIModel globalFFI;

Future<void> initGlobalFFI(DesktopType desktopType, String baseURL) async {
  globalFFI = FFIModel(desktopType, baseURL);
  Get.put<FFIModel>(globalFFI, permanent: true);
}
