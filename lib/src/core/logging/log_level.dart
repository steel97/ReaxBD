/// Log levels for ReaxDB logging system
enum LogLevel {
  /// No logging
  none(0),

  /// Error messages only
  error(1),

  /// Error and warning messages
  warning(2),

  /// Error, warning and info messages
  info(3),

  /// All messages including debug
  debug(4);

  final int value;
  const LogLevel(this.value);

  bool shouldLog(LogLevel messageLevel) {
    return messageLevel.value <= value;
  }
}
