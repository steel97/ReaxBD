/// Encryption types available in ReaxDB
enum EncryptionType {
  /// No encryption - fastest performance
  none,
  
  /// XOR encryption - fast but not cryptographically secure
  /// Best for: Performance-critical apps with basic obfuscation needs
  /// Security: Low - vulnerable to frequency analysis
  xor,
  
  /// AES-256-GCM encryption - cryptographically secure
  /// Best for: Production apps handling sensitive data
  /// Security: High - industry standard encryption
  aes256,
}

/// Extension to provide human-readable descriptions
extension EncryptionTypeExtension on EncryptionType {
  /// Human-readable name
  String get displayName {
    switch (this) {
      case EncryptionType.none:
        return 'No Encryption';
      case EncryptionType.xor:
        return 'XOR (Fast)';
      case EncryptionType.aes256:
        return 'AES-256 (Secure)';
    }
  }
  
  /// Security level description
  String get securityLevel {
    switch (this) {
      case EncryptionType.none:
        return 'None';
      case EncryptionType.xor:
        return 'Low - Basic obfuscation only';
      case EncryptionType.aes256:
        return 'High - Cryptographically secure';
    }
  }
  
  /// Performance impact description
  String get performanceImpact {
    switch (this) {
      case EncryptionType.none:
        return 'No impact';
      case EncryptionType.xor:
        return 'Minimal (~5% overhead)';
      case EncryptionType.aes256:
        return 'Moderate (~15-25% overhead)';
    }
  }
  
  /// Whether this encryption type requires a key
  bool get requiresKey {
    switch (this) {
      case EncryptionType.none:
        return false;
      case EncryptionType.xor:
      case EncryptionType.aes256:
        return true;
    }
  }
}