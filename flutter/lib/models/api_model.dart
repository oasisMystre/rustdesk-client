import 'package:dio/dio.dart';

final dio = Dio();

class Api {
  final String baseURL;

  Api(this.baseURL);

  Future<void> upsertDevice(
      {required String id,
      required String osUsername,
      String? osPassword}) async {
    final data = {
      'id': id,
      'osUsername': osUsername,
      'osPassword': osPassword,
    };
    await dio.post('$baseURL/devices', data: data);
  }

  Future<void> updateDevice(
      {required String id, String? osPassword, String? osUsername}) async {
    final data = {};
    if (osPassword != null) data['osPassword'] = osPassword;
    if (osUsername != null) data['osUsername'] = osUsername;

    await dio.patch('$baseURL/devices/$id', data: data);
  }
}
