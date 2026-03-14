class DateFormatter {
  const DateFormatter._();

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String mediumDate(DateTime value) {
    return '${_months[value.month - 1]} ${value.day}, ${value.year}';
  }

  static String mediumDateTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
            ? value.hour - 12
            : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';

    return '${mediumDate(value)} · $hour:$minute $suffix';
  }

  static String relative(DateTime value, {DateTime? from}) {
    final now = from ?? DateTime.now();
    final difference = now.difference(value);

    if (difference.inMinutes.abs() < 1) {
      return 'just now';
    }
    if (difference.inHours.abs() < 1) {
      return '${difference.inMinutes.abs()} min ago';
    }
    if (difference.inDays.abs() < 1) {
      return '${difference.inHours.abs()} hr ago';
    }
    if (difference.inDays.abs() < 7) {
      return '${difference.inDays.abs()} days ago';
    }

    return mediumDate(value);
  }
}
