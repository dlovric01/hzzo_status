class Account {
  final String id;
  final String oib;
  final String mbo;
  final String dateOfBirth;
  String? lastSaldo;
  DateTime? lastChecked;

  Account({
    required this.id,
    required this.oib,
    required this.mbo,
    required this.dateOfBirth,
    this.lastSaldo,
    this.lastChecked,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'oib': oib,
      'mbo': mbo,
      'dateOfBirth': dateOfBirth,
      'lastSaldo': lastSaldo,
      'lastChecked': lastChecked?.toIso8601String(),
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      oib: json['oib'] as String,
      mbo: json['mbo'] as String,
      dateOfBirth: json['dateOfBirth'] as String,
      lastSaldo: json['lastSaldo'] as String?,
      lastChecked: json['lastChecked'] != null
          ? DateTime.parse(json['lastChecked'] as String)
          : null,
    );
  }

  Account copyWith({
    String? id,
    String? oib,
    String? mbo,
    String? dateOfBirth,
    String? lastSaldo,
    DateTime? lastChecked,
  }) {
    return Account(
      id: id ?? this.id,
      oib: oib ?? this.oib,
      mbo: mbo ?? this.mbo,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      lastSaldo: lastSaldo ?? this.lastSaldo,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}
