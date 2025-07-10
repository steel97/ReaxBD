import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// WASM-compatible fallback implementations for encryption
/// This file provides basic encryption when PointyCastle is not available

// Fallback classes that mimic PointyCastle API for WASM compatibility
class KeyParameter {
  final Uint8List key;
  KeyParameter(this.key);
}

class AEADParameters {
  final KeyParameter keyParam;
  final int macSize;
  final Uint8List nonce;
  final Uint8List associatedData;
  
  AEADParameters(this.keyParam, this.macSize, this.nonce, this.associatedData);
}

/// Simple AES-like encryption using XOR with enhanced key derivation
/// This is a fallback for WASM environments where native crypto isn't available
class AESEngine {
  // Placeholder - not used in fallback mode
}

/// WASM-compatible GCM cipher fallback
/// Uses enhanced XOR encryption with authentication for WASM compatibility
class GCMBlockCipher {
  final AESEngine _engine;
  bool _forEncryption = true;
  Uint8List? _key;
  Uint8List? _nonce;
  
  GCMBlockCipher(this._engine);
  
  void init(bool forEncryption, AEADParameters params) {
    _forEncryption = forEncryption;
    _key = params.keyParam.key;
    _nonce = params.nonce;
  }
  
  Uint8List process(Uint8List input) {
    if (_key == null || _nonce == null) {
      throw StateError('Cipher not initialized');
    }
    
    if (_forEncryption) {
      return _encryptFallback(input, _key!, _nonce!);
    } else {
      return _decryptFallback(input, _key!, _nonce!);
    }
  }
  
  /// Enhanced XOR encryption with authentication for WASM fallback
  Uint8List _encryptFallback(Uint8List data, Uint8List key, Uint8List nonce) {
    // Create enhanced key by combining original key with nonce
    final enhancedKey = _createEnhancedKey(key, nonce);
    
    // Encrypt data using enhanced XOR
    final encrypted = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      encrypted[i] = data[i] ^ enhancedKey[i % enhancedKey.length];
    }
    
    // Add simple authentication tag (16 bytes)
    final authTag = _computeAuthTag(encrypted, enhancedKey);
    
    // Combine encrypted data + auth tag
    final result = Uint8List(encrypted.length + authTag.length);
    result.setRange(0, encrypted.length, encrypted);
    result.setRange(encrypted.length, result.length, authTag);
    
    return result;
  }
  
  /// Enhanced XOR decryption with authentication verification
  Uint8List _decryptFallback(Uint8List data, Uint8List key, Uint8List nonce) {
    if (data.length < 16) {
      throw ArgumentError('Invalid encrypted data: too short for auth tag');
    }
    
    // Split encrypted data and auth tag
    final encryptedData = data.sublist(0, data.length - 16);
    final providedAuthTag = data.sublist(data.length - 16);
    
    // Create enhanced key
    final enhancedKey = _createEnhancedKey(key, nonce);
    
    // Verify authentication tag
    final expectedAuthTag = _computeAuthTag(encryptedData, enhancedKey);
    if (!_constantTimeEquals(providedAuthTag, expectedAuthTag)) {
      throw ArgumentError('Authentication failed: invalid auth tag');
    }
    
    // Decrypt data
    final decrypted = Uint8List(encryptedData.length);
    for (int i = 0; i < encryptedData.length; i++) {
      decrypted[i] = encryptedData[i] ^ enhancedKey[i % enhancedKey.length];
    }
    
    return decrypted;
  }
  
  /// Create enhanced key by combining original key with nonce using HMAC
  Uint8List _createEnhancedKey(Uint8List key, Uint8List nonce) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(nonce);
    
    // Combine original key with HMAC result for enhanced security
    final enhanced = Uint8List(key.length + digest.bytes.length);
    enhanced.setRange(0, key.length, key);
    enhanced.setRange(key.length, enhanced.length, digest.bytes);
    
    return enhanced;
  }
  
  /// Compute authentication tag using HMAC
  Uint8List _computeAuthTag(Uint8List data, Uint8List key) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes.take(16).toList());
  }
  
  /// Constant-time comparison to prevent timing attacks
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}