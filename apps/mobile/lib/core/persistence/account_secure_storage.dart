import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preserve the existing Keychain service and values, using atomic iOS mutations.
/// The plugin's read query includes return flags that SecItemUpdate rejects.
class AccountSecureStorage extends FlutterSecureStorage {
  const AccountSecureStorage({
    IOSOptions options = const IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  }) : super(iOptions: options);

  static const _channel = MethodChannel('field_assist/security');
  static final _iosListeners = <String, List<void Function(String?)>>{};

  @override
  void registerListener({
    required String key,
    required void Function(String?) listener,
  }) {
    if (!Platform.isIOS) {
      return super.registerListener(key: key, listener: listener);
    }
    (_iosListeners[key] ??= []).add(listener);
  }

  @override
  void unregisterListener({
    required String key,
    required void Function(String?) listener,
  }) {
    if (!Platform.isIOS) {
      return super.unregisterListener(key: key, listener: listener);
    }
    _iosListeners[key]?.remove(listener);
  }

  @override
  void unregisterAllListenersForKey({required String key}) {
    if (!Platform.isIOS) return super.unregisterAllListenersForKey(key: key);
    _iosListeners.remove(key);
  }

  @override
  void unregisterAllListeners() {
    if (!Platform.isIOS) return super.unregisterAllListeners();
    _iosListeners.clear();
  }

  Map<String, Object?> _arguments(String key, AppleOptions? options) {
    final selected = options ?? iOptions;
    if (selected.accountName != AppleOptions.defaultAccountName ||
        selected.groupId != null ||
        selected.synchronizable ||
        selected.useSecureEnclave ||
        selected.accessControlFlags.isNotEmpty ||
        ![
          KeychainAccessibility.unlocked,
          KeychainAccessibility.unlocked_this_device,
        ].contains(selected.accessibility)) {
      throw UnsupportedError('Unsupported account Keychain policy.');
    }
    return {'key': key, 'accessibility': selected.accessibility!.name};
  }

  void _notify(String key, String? value) {
    for (final listener in [...?_iosListeners[key]]) {
      listener(value);
    }
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!Platform.isIOS) {
      return super.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    final arguments = _arguments(key, iOptions);
    if (value != null) arguments['value'] = value;
    await _channel.invokeMethod<void>(
      value == null ? 'deleteAccountSecret' : 'writeAccountSecret',
      arguments,
    );
    _notify(key, value);
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!Platform.isIOS) {
      return super.delete(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    await _channel.invokeMethod<void>(
      'deleteAccountSecret',
      _arguments(key, iOptions),
    );
    _notify(key, null);
  }
}
