import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/account.dart';

class AccountStorageService {
  static const String _accountsKey = 'accounts';
  final _secureStorage = const FlutterSecureStorage();

  Future<List<Account>> loadAccounts() async {
    try {
      final accountsJson = await _secureStorage.read(key: _accountsKey);
      if (accountsJson == null || accountsJson.isEmpty) {
        return [];
      }

      final List<dynamic> decoded = json.decode(accountsJson);
      return decoded.map((json) => Account.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAccounts(List<Account> accounts) async {
    try {
      final accountsJson = json.encode(
        accounts.map((account) => account.toJson()).toList(),
      );
      await _secureStorage.write(key: _accountsKey, value: accountsJson);
    } catch (e) {
      // Error saving accounts
    }
  }

  Future<void> addAccount(Account account) async {
    final accounts = await loadAccounts();
    accounts.add(account);
    await saveAccounts(accounts);
  }

  Future<void> updateAccount(Account updatedAccount) async {
    final accounts = await loadAccounts();
    final index = accounts.indexWhere((a) => a.id == updatedAccount.id);
    if (index != -1) {
      accounts[index] = updatedAccount;
      await saveAccounts(accounts);
    }
  }

  Future<void> deleteAccount(String accountId) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await saveAccounts(accounts);
  }
}
