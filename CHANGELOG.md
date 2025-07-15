# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2025-07-15

### Fixed
- Fixed pub.dev static analysis issues
- Better error handling in code
- Improved code quality

### Added
- API documentation for all public methods

## [1.2.1] - 2025-07-15

### Fixed
- Minor fixes and code improvements

## [1.2.0] - 2025-07-11

### Added
- **WASM Compatibility**: Full support for Dart's WASM runtime with automatic fallback encryption
- **Enhanced Encryption API**: New `EncryptionType` enum for better encryption control
- **Encryption Factory Methods**: `DatabaseConfig.withXorEncryption()` and `DatabaseConfig.withAes256Encryption()`
- **WASM Fallback Encryption**: HMAC-based encryption for WASM environments when PointyCastle is unavailable
- **Runtime Detection**: Automatic detection of WASM runtime with appropriate warnings
- **Encryption Metadata**: Enhanced metadata including runtime environment and fallback status

### Improved
- **AES-256 Performance**: 40% faster AES encryption (138-180ms vs 237ms) using PointyCastle 4.0.0
- **WAL Recovery**: Fixed Write-Ahead Log recovery issues with proper pending write flushing
- **Code Documentation**: Updated README with new encryption API examples and WASM compatibility section

### Fixed
- **WAL Test Failures**: Resolved race conditions in Write-Ahead Log tests
- **Tombstone Recovery**: Fixed delete entry recovery in WAL mixed operations
- **Async Flush Issues**: Improved pending write flushing in WAL close operations

### Technical
- **Conditional Imports**: Smart import system for WASM compatibility
- **Fallback Implementation**: WASM-compatible encryption using only Dart's built-in crypto library
- **API Compatibility**: Maintains backward compatibility while adding new features

## [1.1.1] - 2025-06-15

### Added
- **Secondary Indexes**: Query any field with lightning speed
- **Query Builder**: Powerful API for complex queries  
- **Range Queries**: Find documents between values
- **Auto Index Updates**: Indexes stay in sync automatically

### Improved
- **Query Performance**: Significant improvements in indexed queries
- **Index Management**: Better index creation and maintenance

## [1.0.1] - 2025-05-20

### Added
- **4.4x faster writes**: Now 21,000+ operations per second
- **40% faster batch operations**: Improved batch processing

### Improved
- **Write Performance**: Major optimizations in write operations
- **Batch Processing**: Enhanced batch operation efficiency

## [1.0.0] - 2025-05-01

### Added
- Initial release of ReaxDB
- **High Performance**: Zero-copy serialization and multi-level caching system
- **Security**: Built-in encryption with customizable keys
- **ACID Transactions**: Full transaction support with isolation levels
- **Concurrent Operations**: Connection pooling and batch processing
- **Mobile Optimized**: Hybrid storage engine designed for mobile devices
- **Real-time Streams**: Live data change notifications with pattern matching