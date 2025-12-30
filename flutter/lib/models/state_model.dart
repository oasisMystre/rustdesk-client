import 'package:flutter_hbb/consts.dart';
import 'package:get/get.dart';

class StateModel extends GetxController {
  late final Rx<DesktopType> desktopType;

  StateModel(DesktopType desktopType) {
    this.desktopType = desktopType.obs;
  }

  bool get isMain => desktopType.value == DesktopType.main;
}
