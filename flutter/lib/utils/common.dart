import 'dart:io';

bool get isMobile => Platform.isAndroid || Platform.isAndroid;
bool get isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
