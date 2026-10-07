import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmobile/src/config/app_config.dart';
import 'package:hrmobile/src/middleware/dio_logging_interceptor.dart';
import 'auth_session_test.dart' show TestAdapter, jsonResponse;

void main() {
  test('API prefix is added once and debug errors omit credentials', () async {
    for (final url in [
      'https://example.test',
      'https://example.test/',
      'https://example.test/api/'
    ]) {
      dotenv.loadFromString(envString: 'API_BASE_URL=$url');
      expect(AppConfig.baseUrl, 'https://example.test/api');
    }
    final logs = <Object>[];
    final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
    dio.interceptors.add(DioLoggingInterceptor(logPrint: logs.add));
    dio.httpClientAdapter = TestAdapter((options) {
      expect(options.uri.path, '/api/auth/login');
      expect(options.data['password'], 'secret-password');
      return jsonResponse({'message': 'Invalid credentials'}, 401);
    });
    await expectLater(
        dio.post<Map<String, dynamic>>('/auth/login',
            data: {'password': 'secret-password'}),
        throwsA(isA<DioException>()));
    expect(logs.join(), contains('Invalid credentials'));
    expect(logs.join(), contains('401'));
    expect(logs.join(), isNot(contains('secret-password')));
    logs.clear();
    dio.httpClientAdapter =
        TestAdapter((_) => jsonResponse({'token': 'secret-token'}));
    final response = await dio.post<Map<String, dynamic>>('/auth/login');
    expect(response.data?['token'], 'secret-token');
    expect(logs.join(), isNot(contains('secret-token')));
    dio.close();
  });
}
