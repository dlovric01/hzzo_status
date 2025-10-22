import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hzzo_saldo/hzzo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HzzoStatusScreen extends StatefulWidget {
  const HzzoStatusScreen({super.key});

  @override
  State<HzzoStatusScreen> createState() => _HzzoStatusScreenState();
}

class _HzzoStatusScreenState extends State<HzzoStatusScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oibController = TextEditingController();
  final _mboController = TextEditingController();
  final _captchaController = TextEditingController();
  final HzzoService _hzzoService = HzzoService();

  DateTime? _selectedDate;
  Uint8List? _captchaImageBytes;
  bool _isLoadingCaptcha = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _loadCaptcha();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _oibController.text = prefs.getString('oib') ?? '';
      _mboController.text = prefs.getString('mbo') ?? '';
      final savedDate = prefs.getString('dateOfBirth');
      if (savedDate != null && savedDate.isNotEmpty) {
        try {
          // Remove trailing dot if present before splitting
          final cleanDate = savedDate.replaceAll('.', ' ').trim();
          final parts = cleanDate
              .split(' ')
              .where((s) => s.isNotEmpty)
              .toList();
          if (parts.length == 3) {
            _selectedDate = DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        } catch (e) {
          // Invalid date format, ignore
        }
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('oib', _oibController.text);
    await prefs.setString('mbo', _mboController.text);
    if (_selectedDate != null) {
      await prefs.setString('dateOfBirth', _formatDate(_selectedDate));
    }
  }

  @override
  void dispose() {
    _oibController.dispose();
    _mboController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _isLoadingCaptcha = true;
      _captchaImageBytes = null;
    });

    try {
      final imageBytes = await _hzzoService.getCaptchaImage();
      setState(() {
        _captchaImageBytes = imageBytes;
        _isLoadingCaptcha = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCaptcha = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Greška prilikom učitavanja CAPTCHA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshCaptcha() async {
    _captchaController.clear();
    _hzzoService.refreshSession();
    await _loadCaptcha();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    // Format without leading zeros and with trailing dot to match browser format
    return '${date.day}.${date.month}.${date.year}.';
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Molimo ispunite sva polja'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await _hzzoService.checkInsuranceStatus(
        oib: _oibController.text,
        mbo: _mboController.text,
        dateOfBirth: _formatDate(_selectedDate),
        captchaCode: _captchaController.text,
      );

      setState(() {
        _isSubmitting = false;
      });

      if (result != null && mounted) {
        // Save data on successful request
        await _saveData();
        // Show result in a dialog or navigate to result screen
        _showResultDialog(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Greška prilikom provjere statusa'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Greška: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showResultDialog(String htmlResult) {
    final result = _extractStatusMessage(htmlResult);

    // Determine color based on saldo value
    // Negative = credit/preplata (green), Positive = debt/dug (red)
    Color backgroundColor = const Color(
      0xFFFAE5E5,
    ); // default pink/red for errors
    if (!result.containsKey('error') && result['saldo'] != null) {
      final saldoText = result['saldo']!.trim();
      // Check if first character is minus sign
      if (saldoText.startsWith('-')) {
        // Negative = preplata (credit) - green
        backgroundColor = Colors.green.shade200; // light green
      } else {
        // Positive = dug (debt) - red
        backgroundColor = Colors.red.shade200; // light red
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Rezultati Provjere',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.of(context).pop();
                _refreshCaptcha();
              },
            ),
          ],
        ),
        content: result.containsKey('error')
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    result['error']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OIB',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result['oib'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Saldo',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result['saldo'] ?? '',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Provjereno: ${result['timestamp'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                    if (result['note']?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          result['note']!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _refreshCaptcha();
            },
            child: const Text('U redu'),
          ),
        ],
      ),
    );
  }

  Map<String, String> _extractStatusMessage(String html) {
    // Extract data from CPH1_litOdgovor span
    final resultPattern = RegExp(
      r'<span[^>]*id="CPH1_litOdgovor"[^>]*>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    final resultMatch = resultPattern.firstMatch(html);

    if (resultMatch == null) {
      return {'error': 'Nema podataka u odgovoru'};
    }

    final resultHtml = resultMatch.group(1) ?? '';

    // Check if result contains actual data (not just form with validation messages)
    // The result HTML should contain the actual result data
    if (!resultHtml.contains('Rezultati Provjere')) {
      // This is likely just the form being redisplayed with an error
      return {
        'error':
            'Pogrešan CAPTCHA kod ili nevažeći podaci. Molimo pokušajte ponovno.',
      };
    }

    // Extract OIB
    final oibPattern = RegExp(
      r'<p>OIB</p><p><strong>(.*?)</strong></p>',
      dotAll: true,
    );
    final oibMatch = oibPattern.firstMatch(resultHtml);
    final oib = oibMatch?.group(1)?.trim() ?? '';

    // Extract Saldo
    final saldoPattern = RegExp(
      r'<p>Saldo</p><p><strong>(.*?)</strong></p>',
      dotAll: true,
    );
    final saldoMatch = saldoPattern.firstMatch(resultHtml);
    final saldo = saldoMatch?.group(1)?.trim() ?? '';

    // Extract timestamp
    final timePattern = RegExp(r'<p>Provjereno:\s*(.*?)</p>', dotAll: true);
    final timeMatch = timePattern.firstMatch(resultHtml);
    final timestamp = timeMatch?.group(1)?.trim() ?? '';

    // Extract note/message
    final notePattern = RegExp(r'<h4>(.*?)</h4>', dotAll: true);
    final noteMatch = notePattern.firstMatch(resultHtml);
    final note = noteMatch?.group(1)?.trim() ?? '';

    return {'oib': oib, 'saldo': saldo, 'timestamp': timestamp, 'note': note};
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: const Color(0xFF005BAA),
          title: const Text(
            'HZZO - Saldo',
            style: TextStyle(color: Colors.white),
          ),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Header section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF005BAA),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Provjera salda dopunskog osiguranja',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Unesite svoje podatke za provjeru salda',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Form section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // OIB Field
                          const Text(
                            'OIB (Osobni identifikacijski broj)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _oibController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                            ],
                            decoration: InputDecoration(
                              hintText: 'Unesite 11-znamenkasti OIB',
                              prefixIcon: const Icon(Icons.badge),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'OIB je obavezan';
                              }
                              if (value.length != 11) {
                                return 'OIB mora imati 11 znamenki';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // MBO Field
                          const Text(
                            'MBO (Matični broj osiguranika)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _mboController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: InputDecoration(
                              hintText: 'Unesite 9-znamenkasti MBO',
                              prefixIcon: const Icon(Icons.credit_card),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'MBO je obavezan';
                              }
                              if (value.length != 9) {
                                return 'MBO mora imati 9 znamenki';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Date of Birth Field
                          const Text(
                            'Datum rođenja',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _selectDate(context),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                hintText: 'Odaberite datum rođenja',
                                prefixIcon: const Icon(Icons.calendar_today),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              child: Text(
                                _selectedDate != null
                                    ? _formatDate(_selectedDate)
                                    : 'DD.MM.GGGG',
                                style: TextStyle(
                                  color: _selectedDate != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                          if (_selectedDate == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 8, left: 12),
                              child: Text(
                                'Datum rođenja je obavezan',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),

                          // CAPTCHA Section
                          const Text(
                            'Kod sa slike',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // CAPTCHA Image
                          Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: _isLoadingCaptcha
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : _captchaImageBytes != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: Image.memory(
                                              _captchaImageBytes!,
                                              fit: BoxFit.contain,
                                              filterQuality:
                                                  FilterQuality.medium,
                                            ),
                                          )
                                        : const Center(
                                            child: Text(
                                              'CAPTCHA nije učitan',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: _isLoadingCaptcha
                                      ? null
                                      : _refreshCaptcha,
                                  tooltip: 'Osvježi kod',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // CAPTCHA Input
                          TextFormField(
                            controller: _captchaController,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submitForm(),
                            decoration: InputDecoration(
                              hintText: 'Unesite kod sa slike',
                              prefixIcon: const Icon(Icons.security),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Kod sa slike je obavezan';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF005BAA),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Provjeri saldo',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Info text
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'OIB i MBO možete pronaći na zdravstvenoj iskaznici',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
