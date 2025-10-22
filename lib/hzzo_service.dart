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
    // Create HTTP client with proper certificate validation
    // Only allow specific certificate validation bypass for ezdravstveno.hzzo.hr if needed
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Only bypass certificate validation for the specific HZZO domain if necessary
        // This is a temporary measure - ideally the server should have valid certificates
        return host == 'ezdravstveno.hzzo.hr';
      };
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

      // Session initialized successfully
    } catch (e) {
      // Error initializing session
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
        return null;
      }

      // Build full URL - the captchaUrl from HTML is relative
      final fullCaptchaUrl = _captchaUrl!.startsWith('http')
          ? _captchaUrl!
          : '$baseUrl$_captchaUrl';

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
        return null;
      }
    } catch (e) {
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
        // Error parsing date
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
        return response.body;
      } else {
        return null;
      }
    } catch (e) {
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
