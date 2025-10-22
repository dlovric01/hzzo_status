// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class HzzoService {
  static const String baseUrl = 'https://ezdravstveno.hzzo.hr';
  static const String statusPageUrl =
      '$baseUrl/Public/SaldoDopunskogOsiguranja/Default.aspx';

  final Map<String, String> _cookies = {};
  String? _viewState;
  String? _viewStateGenerator;
  String? _eventValidation;
  String? _requestVerificationToken;
  String? _captchaUrl;
  String? _dxScript;
  String? _dxCss;

  late final http.Client _httpClient;

  HzzoService() {
    // Create HTTP client that accepts self-signed certificates
    // This is necessary for some government websites with certificate issues
    final httpClient = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    _httpClient = IOClient(httpClient);
  }

  Future<void> initializeSession() async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse(statusPageUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // Extract cookies
      final cookies = response.headers['set-cookie'];
      if (cookies != null) {
        _parseCookies(cookies);
      }

      // Extract ASP.NET ViewState and other hidden fields
      final html = response.body;
      _viewState = _extractValue(html, r'id="__VIEWSTATE" value="([^"]*)"');
      _viewStateGenerator = _extractValue(
        html,
        r'id="__VIEWSTATEGENERATOR" value="([^"]*)"',
      );
      _eventValidation = _extractValue(
        html,
        r'id="__EVENTVALIDATION" value="([^"]*)"',
      );
      _requestVerificationToken = _extractValue(
        html,
        r'name="__RequestVerificationToken"[^>]*value="([^"]*)"',
      );

      // Extract CAPTCHA image URL (DevExpress CAPTCHA uses DXB.axd)
      _captchaUrl = _extractValue(
        html,
        r'captcha_IMG[^>]*src="([^"]*)"',
      );

      // Extract DXScript and DXCss values
      _dxScript = _extractValue(html, r'id="DXScript"[^>]*value="([^"]*)"');
      _dxCss = _extractValue(html, r'id="DXCss"[^>]*value="([^"]*)"');

      print('Session initialized');
      print('ViewState: ${_viewState?.substring(0, 50)}...');
      print('CAPTCHA URL: $_captchaUrl');
    } catch (e) {
      print('Error initializing session: $e');
      rethrow;
    }
  }

  Future<Uint8List?> getCaptchaImage() async {
    try {
      // First, ensure we have a session
      if (_viewState == null || _captchaUrl == null) {
        await initializeSession();
      }

      if (_captchaUrl == null) {
        print('CAPTCHA URL not found in page');
        return null;
      }

      // Build full URL - the captchaUrl from HTML is relative
      final fullCaptchaUrl = _captchaUrl!.startsWith('http')
          ? _captchaUrl!
          : '$baseUrl$_captchaUrl';

      print('Fetching CAPTCHA from: $fullCaptchaUrl');

      final response = await _httpClient
          .get(
            Uri.parse(fullCaptchaUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Cookie': _getCookieHeader(),
              'Referer': statusPageUrl,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Failed to load captcha: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error loading captcha: $e');
      return null;
    }
  }

  Future<String?> checkInsuranceStatus({
    required String oib,
    required String mbo,
    required String dateOfBirth,
    required String captchaCode,
  }) async {
    try {
      // Ensure we have a valid session
      if (_viewState == null) {
        await initializeSession();
      }

      // Parse date for state - format is "12.7.1998."
      DateTime? parsedDate;
      try {
        final parts = dateOfBirth.replaceAll('.', '').split(' ');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          final dateParts = dateOfBirth.split('.');
          if (dateParts.length >= 3) {
            parsedDate = DateTime.utc(
              int.parse(dateParts[2]),
              int.parse(dateParts[1]),
              int.parse(dateParts[0]),
            );
          }
        }
      } catch (e) {
        print('Error parsing date: $e');
      }

      // Get current date for calendar visible date
      final now = DateTime.now();
      final visibleDate =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      final selectedDate = parsedDate != null
          ? '${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.year}'
          : '';

      final body = {
        '__EVENTTARGET': '',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': _viewState ?? '',
        '__VIEWSTATEGENERATOR': _viewStateGenerator ?? '',
        '__EVENTVALIDATION': _eventValidation ?? '',
        '__RequestVerificationToken': _requestVerificationToken ?? '',
        'ctl00\$CPH1\$txtOIB\$State': '{"validationState":""}',
        'ctl00\$CPH1\$txtOIB': oib,
        'ctl00\$CPH1\$txtMBO\$State': '{"validationState":""}',
        'ctl00\$CPH1\$txtMBO': mbo,
        'ctl00\$CPH1\$deDatumRodjenja\$State':
            '{"rawValue":"${parsedDate?.millisecondsSinceEpoch ?? ""}","useMinDateInsteadOfNull":false,"validationState":""}',
        'ctl00\$CPH1\$deDatumRodjenja': dateOfBirth,
        'ctl00\$CPH1\$deDatumRodjenja\$C':
            '{"visibleDate":"$visibleDate","initialVisibleDate":"$visibleDate","selectedDates":["$selectedDate"]}',
        'ctl00\$CPH1\$captcha\$TB\$State': '{"validationState":""}',
        'ctl00\$CPH1\$captcha\$TB': captchaCode,
        'ctl00\$CPH1\$btnPosalji': 'Provjeri stanje salda',
        'DXScript': _dxScript ?? '',
        'DXCss': _dxCss ?? '',
      };

      print('Submitting form with data:');
      print('OIB: $oib, MBO: $mbo, DOB: $dateOfBirth, Captcha: $captchaCode');
      print('Date rawValue: ${parsedDate?.millisecondsSinceEpoch}');

      final response = await _httpClient
          .post(
            Uri.parse(statusPageUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Cookie': _getCookieHeader(),
              'Referer': statusPageUrl,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print('Response received, length: ${response.body.length}');

        // Print snippet of response to check for result
        if (response.body.contains('CPH1_litOdgovor')) {
          final resultPattern = RegExp(
            r'<span[^>]*id="CPH1_litOdgovor"[^>]*>(.*?)</span>',
            caseSensitive: false,
            dotAll: true,
          );
          final match = resultPattern.firstMatch(response.body);
          if (match != null) {
            print('Found result section: ${match.group(1)?.substring(0, 200)}...');
          }
        }

        return response.body;
      } else {
        print('Failed to check status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error checking insurance status: $e');
      return null;
    }
  }

  String? _extractValue(String html, String pattern) {
    final regex = RegExp(pattern);
    final match = regex.firstMatch(html);
    return match?.group(1);
  }

  void _parseCookies(String cookieHeader) {
    final cookies = cookieHeader.split(',');
    for (final cookie in cookies) {
      final parts = cookie.split(';')[0].split('=');
      if (parts.length == 2) {
        _cookies[parts[0].trim()] = parts[1].trim();
      }
    }
  }

  String _getCookieHeader() {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void refreshSession() {
    _cookies.clear();
    _viewState = null;
    _viewStateGenerator = null;
    _eventValidation = null;
    _requestVerificationToken = null;
    _captchaUrl = null;
    _dxScript = null;
    _dxCss = null;
  }

  void dispose() {
    _httpClient.close();
  }
}
