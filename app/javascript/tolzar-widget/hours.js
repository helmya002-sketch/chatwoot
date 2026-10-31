// Tolzar widget: is the team in office hours right now, in the inbox's time zone? From the inbox's working hours
// (day_of_week 0 = Sunday, open_all_day / closed_all_day, open/close hour and minutes). Without hours turned on,
// the team counts as available.

const DAYS = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

// { day, minutes } for `now` in `timeZone` (falls back to UTC for an unknown zone).
export function localTime(now, timeZone) {
  let parts;
  try {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone || 'UTC',
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(now);
  } catch {
    return localTime(now, 'UTC');
  }
  const get = type => parts.find(p => p.type === type)?.value;
  return {
    day: DAYS[get('weekday')],
    minutes: Number(get('hour')) * 60 + Number(get('minute')),
  };
}

export function isOpen({ enabled, hours, timeZone }, now = new Date()) {
  if (!enabled) return true;
  const { day, minutes } = localTime(now, timeZone);
  const today = (hours || []).find(h => Number(h.day_of_week) === day);
  if (!today || today.closed_all_day) return false;
  if (today.open_all_day) return true;
  const open = Number(today.open_hour) * 60 + Number(today.open_minutes || 0);
  const close =
    Number(today.close_hour) * 60 + Number(today.close_minutes || 0);
  return minutes >= open && minutes < close;
}
