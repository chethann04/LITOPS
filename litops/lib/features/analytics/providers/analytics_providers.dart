import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/enums/enums.dart';

final analyticsSummaryProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  Future<Map<String, dynamic>> fetchSummary() async {
    final client = SupabaseConfig.client;
    try {
      final regsRes = await client
          .from(SupabaseTables.registrations)
          .select('id')
          .eq('is_cancelled', false);
      final totalRegistrations = (regsRes as List).length;

      final eventsRes = await client
          .from(SupabaseTables.events)
          .select('id');
      final totalEvents = (eventsRes as List).length;

      final attendanceRes = await client
          .from(SupabaseTables.attendance)
          .select('id');
      final totalAttendance = (attendanceRes as List).length;

      return {
        'totalRegistrations': totalRegistrations,
        'totalEvents': totalEvents,
        'totalAttendance': totalAttendance,
        'attendanceRate': totalRegistrations > 0 
            ? (totalAttendance / totalRegistrations * 100).toStringAsFixed(1)
            : '0',
      };
    } catch (_) {
      return {
        'totalRegistrations': 0,
        'totalEvents': 0,
        'totalAttendance': 0,
        'attendanceRate': '0',
      };
    }
  }

  yield await fetchSummary();
  await for (final _ in Stream.periodic(const Duration(seconds: 6))) {
    yield await fetchSummary();
  }
});

final categoryParticipationProvider = FutureProvider<Map<EventCategory, int>>((ref) async {
  final client = SupabaseConfig.client;
  
  // Fetch registrations with event categories
  final response = await client
      .from(SupabaseTables.registrations)
      .select('events(category)')
      .eq('is_cancelled', false);
      
  final Map<EventCategory, int> counts = {};
  for (final item in response as List) {
    final event = item['events'] as Map<String, dynamic>?;
    if (event != null && event['category'] != null) {
      final category = EventCategory.fromString(event['category'] as String);
      counts[category] = (counts[category] ?? 0) + 1;
    }
  }
  
  return counts;
});

final registrationTrendProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = SupabaseConfig.client;
  
  // Fetch registration dates
  final response = await client
      .from(SupabaseTables.registrations)
      .select('registered_at')
      .eq('is_cancelled', false)
      .order('registered_at', ascending: true);
      
  final List<Map<String, dynamic>> trend = [];
  final Map<String, int> dailyCounts = {};
  
  for (final item in response as List) {
    final dateStr = (item['registered_at'] as String).split('T').first;
    dailyCounts[dateStr] = (dailyCounts[dateStr] ?? 0) + 1;
  }
  
  // Sort and format for chart (take last 7 days with data)
  final sortedDates = dailyCounts.keys.toList()..sort();
  final last7Dates = sortedDates.length > 7 
      ? sortedDates.sublist(sortedDates.length - 7) 
      : sortedDates;
      
  for (final date in last7Dates) {
    trend.add({
      'date': date,
      'count': dailyCounts[date],
    });
  }
  
  return trend;
});

final branchParticipationProvider = FutureProvider<Map<String, int>>((ref) async {
  final client = SupabaseConfig.client;
  
  final response = await client
      .from(SupabaseTables.registrations)
      .select('student_master(branch)')
      .eq('is_cancelled', false);
      
  final Map<String, int> counts = {};
  for (final item in response as List) {
    final student = item['student_master'] as Map<String, dynamic>?;
    if (student != null && student['branch'] != null) {
      final branch = student['branch'] as String;
      counts[branch] = (counts[branch] ?? 0) + 1;
    }
  }
  
  // Sort by count descending and take top 5
  final sortedKeys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final Map<String, int> top5 = {};
  for (var i = 0; i < sortedKeys.length && i < 5; i++) {
    top5[sortedKeys[i]] = counts[sortedKeys[i]]!;
  }
  
  return top5;
});

