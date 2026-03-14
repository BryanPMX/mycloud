class FileSizeFormatter {
  const FileSizeFormatter._();

  static const List<String> _units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  static String compact(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    var unitIndex = 0;
    double value = bytes.toDouble();
    while (value >= 1024 && unitIndex < _units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final decimals = value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${_units[unitIndex]}';
  }
}
