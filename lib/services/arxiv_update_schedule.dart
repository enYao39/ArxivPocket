/// Helper for arXiv's weekday announcement schedule (Sun–Thu 20:00 US/Eastern).
class ArxivUpdateSchedule {
  const ArxivUpdateSchedule._();

  /// Returns true if [utcTime] falls within US Daylight Saving Time (EDT, UTC-4).
  ///
  /// US DST starts on the 2nd Sunday of March at 02:00 EST (07:00 UTC) and
  /// ends on the 1st Sunday of November at 02:00 EDT (06:00 UTC).
  static bool isUsDaylightSavingTime(DateTime utcTime) {
    final utc = utcTime.toUtc();
    final year = utc.year;

    final marchFirst = DateTime.utc(year, DateTime.march, 1);
    final daysToFirstSundayMarch = (DateTime.sunday - marchFirst.weekday) % 7;
    final secondSundayMarchDay = 1 + daysToFirstSundayMarch + 7;
    final dstStartUtc = DateTime.utc(year, DateTime.march, secondSundayMarchDay, 7);

    final novFirst = DateTime.utc(year, DateTime.november, 1);
    final daysToFirstSundayNov = (DateTime.sunday - novFirst.weekday) % 7;
    final firstSundayNovDay = 1 + daysToFirstSundayNov;
    final dstEndUtc = DateTime.utc(year, DateTime.november, firstSundayNovDay, 6);

    return !utc.isBefore(dstStartUtc) && utc.isBefore(dstEndUtc);
  }

  /// Converts a [DateTime] to US/Eastern wall-clock time (stored as UTC fields).
  static DateTime toEasternWallClock(DateTime time) {
    final utc = time.toUtc();
    final offsetHours = isUsDaylightSavingTime(utc) ? -4 : -5;
    return utc.add(Duration(hours: offsetHours));
  }

  /// Converts a US/Eastern wall-clock [DateTime] back to UTC.
  static DateTime easternWallClockToUtc(DateTime easternWallClock) {
    // Check with standard EST (-5) first, then refine if EDT (-4) applies.
    final estGuess = DateTime.utc(
      easternWallClock.year,
      easternWallClock.month,
      easternWallClock.day,
      easternWallClock.hour,
      easternWallClock.minute,
      easternWallClock.second,
    ).add(const Duration(hours: 5));
    if (isUsDaylightSavingTime(estGuess)) {
      return estGuess.subtract(const Duration(hours: 1));
    }
    return estGuess;
  }

  static bool _isAnnouncementDay(int weekday) {
    return weekday == DateTime.sunday ||
        weekday == DateTime.monday ||
        weekday == DateTime.tuesday ||
        weekday == DateTime.wednesday ||
        weekday == DateTime.thursday;
  }

  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final first = DateTime.utc(year, month, 1);
    final offset = (weekday - first.weekday) % 7;
    return DateTime.utc(year, month, 1 + offset + (n - 1) * 7);
  }

  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final nextMonthFirst = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    final lastDay = nextMonthFirst.subtract(const Duration(days: 1));
    final offset = (lastDay.weekday - weekday) % 7;
    return lastDay.subtract(Duration(days: offset));
  }

  static bool _isObservedFixedHoliday(DateTime day, int month, int targetDay) {
    final actual = DateTime.utc(day.year, month, targetDay);
    if (actual.weekday == DateTime.saturday) {
      return day == actual.subtract(const Duration(days: 1));
    }
    if (actual.weekday == DateTime.sunday) {
      return day == actual.add(const Duration(days: 1));
    }
    return day == actual;
  }

  /// Returns the holiday name if [easternDay] is an arXiv/Cornell US holiday.
  static String? holidayNameForEasternDate(DateTime easternDay) {
    final day = DateTime.utc(easternDay.year, easternDay.month, easternDay.day);

    if (_isObservedFixedHoliday(day, DateTime.january, 1)) {
      return "New Year's Day";
    }
    if (day == _nthWeekdayOfMonth(day.year, DateTime.january, DateTime.monday, 3)) {
      return "Martin Luther King Jr. Day";
    }
    if (day == _lastWeekdayOfMonth(day.year, DateTime.may, DateTime.monday)) {
      return "Memorial Day";
    }
    if (_isObservedFixedHoliday(day, DateTime.june, 19)) {
      return "Juneteenth";
    }
    if (_isObservedFixedHoliday(day, DateTime.july, 4)) {
      return "Independence Day";
    }
    if (day == _nthWeekdayOfMonth(day.year, DateTime.september, DateTime.monday, 1)) {
      return "Labor Day";
    }
    final thanksgiving = _nthWeekdayOfMonth(
      day.year,
      DateTime.november,
      DateTime.thursday,
      4,
    );
    if (day == thanksgiving || day == thanksgiving.add(const Duration(days: 1))) {
      return "Thanksgiving break";
    }
    if (day.month == DateTime.december && day.day >= 24) {
      return "Winter break";
    }
    return null;
  }

  /// Returns a human-readable reason if arXiv does not announce new papers today
  /// (weekend or arXiv holiday in US/Eastern), or null on normal announcement days.
  static String? noAnnouncementReason(DateTime nowUtc) {
    final eastern = toEasternWallClock(nowUtc);
    final holiday = holidayNameForEasternDate(eastern);
    if (holiday != null) {
      return "No new arXiv papers today ($holiday).";
    }
    if (!_isAnnouncementDay(eastern.weekday)) {
      return "No new arXiv papers today (weekend schedule).";
    }
    return null;
  }

  /// Returns the most recent arXiv announcement timestamp in UTC at or before [nowUtc].
  static DateTime latestAnnouncementUtc(DateTime nowUtc) {
    final eastern = toEasternWallClock(nowUtc);
    var candidateDay = DateTime.utc(eastern.year, eastern.month, eastern.day);

    for (var i = 0; i < 21; i++) {
      if (_isAnnouncementDay(candidateDay.weekday) &&
          holidayNameForEasternDate(candidateDay) == null) {
        final candidateEastern = DateTime.utc(
          candidateDay.year,
          candidateDay.month,
          candidateDay.day,
          20,
        );
        if (!candidateEastern.isAfter(eastern)) {
          return easternWallClockToUtc(candidateEastern);
        }
      }
      candidateDay = candidateDay.subtract(const Duration(days: 1));
    }

    return nowUtc.toUtc();
  }

  /// Returns the next scheduled arXiv announcement timestamp in UTC after [nowUtc].
  static DateTime nextAnnouncementUtc(DateTime nowUtc) {
    final eastern = toEasternWallClock(nowUtc);
    var candidateDay = DateTime.utc(eastern.year, eastern.month, eastern.day);

    for (var i = 0; i < 21; i++) {
      if (_isAnnouncementDay(candidateDay.weekday) &&
          holidayNameForEasternDate(candidateDay) == null) {
        final candidateEastern = DateTime.utc(
          candidateDay.year,
          candidateDay.month,
          candidateDay.day,
          20,
        );
        if (candidateEastern.isAfter(eastern)) {
          return easternWallClockToUtc(candidateEastern);
        }
      }
      candidateDay = candidateDay.add(const Duration(days: 1));
    }

    return nowUtc.toUtc().add(const Duration(days: 1));
  }

  /// Whether an arXiv announcement window has passed since [lastFetchedUtc].
  static bool hasNewAnnouncementSince(
    DateTime? lastFetchedUtc, {
    DateTime? nowUtc,
  }) {
    if (lastFetchedUtc == null) {
      return true;
    }
    final currentUtc = (nowUtc ?? DateTime.now()).toUtc();
    final latestWindow = latestAnnouncementUtc(currentUtc);
    return lastFetchedUtc.toUtc().isBefore(latestWindow);
  }

  /// Returns whether a `YYYY-MM-DD` submission date falls inside the
  /// submission window for the most recent arXiv announcement.
  static bool isSubmittedInLatestWindow(
    String publishedAt, {
    DateTime? nowUtc,
  }) {
    final trimmed = publishedAt.trim();
    if (trimmed.length < 10) return false;
    final parsed = DateTime.tryParse(trimmed.substring(0, 10));
    if (parsed == null) return false;

    final currentUtc = (nowUtc ?? DateTime.now()).toUtc();
    final latestUtc = latestAnnouncementUtc(currentUtc);
    final prevUtc = latestAnnouncementUtc(
      latestUtc.subtract(const Duration(minutes: 1)),
    );

    final latestEastern = toEasternWallClock(latestUtc);
    final prevEastern = toEasternWallClock(prevUtc);
    final startDay = DateTime.utc(
      prevEastern.year,
      prevEastern.month,
      prevEastern.day,
    );
    final endDay = DateTime.utc(
      latestEastern.year,
      latestEastern.month,
      latestEastern.day,
    );
    final paperDay = DateTime.utc(parsed.year, parsed.month, parsed.day);
    return !paperDay.isBefore(startDay) && !paperDay.isAfter(endDay);
  }

  /// Formats the remaining time until the next arXiv announcement.
  static String formatTimeUntilNextUpdate(DateTime nowUtc) {
    final nextUtc = nextAnnouncementUtc(nowUtc);
    final diff = nextUtc.difference(nowUtc.toUtc());
    if (diff.inMinutes < 1) {
      return "less than a minute";
    }
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) {
      return "${days}d ${hours}h";
    }
    if (hours > 0) {
      return "${hours}h ${minutes}m";
    }
    return "${minutes}m";
  }
}
