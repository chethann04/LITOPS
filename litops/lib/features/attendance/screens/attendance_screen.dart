import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../auth/providers/auth_provider.dart';

final eventAttendanceProvider = StreamProvider.family<Map<String, dynamic>, String>((ref, eventId) async* {
  Future<Map<String, dynamic>> fetch() async {
    try {
      final regs = await SupabaseConfig.client
          .from(SupabaseTables.registrations)
          .select('id,student_id,student_master(name,usn,branch)')
          .eq('event_id', eventId)
          .eq('is_cancelled', false);
      final att = await SupabaseConfig.client
          .from(SupabaseTables.attendance)
          .select('registration_id')
          .eq('event_id', eventId);
      final attIds = (att as List).map((a) => a['registration_id']).toSet();
      return {'registrations': regs, 'attended': attIds, 'total': (regs as List).length, 'attendedCount': attIds.length};
    } catch (e) {
      debugPrint('Error fetching event attendance: $e');
      return {'registrations': [], 'attended': <dynamic>{}, 'total': 0, 'attendedCount': 0};
    }
  }

  yield await fetch();
  await for (final _ in Stream.periodic(const Duration(seconds: 4))) {
    yield await fetch();
  }
});

final attendanceEventsProvider = StreamProvider<List<Event>>((ref) async* {
  Future<List<Event>> fetchEvents() async {
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseTables.events)
          .select()
          .inFilter('status', ['ongoing', 'registration_open', 'registration_closed']);
      final list = (res as List).map((e) => Event.fromJson(e)).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e) {
      debugPrint('Error fetching attendance events: $e');
      return [];
    }
  }

  yield await fetchEvents();
  await for (final _ in Stream.periodic(const Duration(seconds: 4))) {
    yield await fetchEvents();
  }
});

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    final eventsAsync = ref.watch(attendanceEventsProvider);
    return Scaffold(
      backgroundColor: LitColors.void_,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Attendance',
          style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: 16, color: LitColors.bone),
        ),
      ),
      body: role.canMarkAttendance
          ? eventsAsync.when(
              loading: () => const LoadingView(),
              error: (err, _) => Center(child: Text('Error loading events: $err', style: const TextStyle(color: LitColors.coral))),
              data: (events) {
                if (events.isEmpty) return const EmptyView(icon: Icons.event_busy, title: 'No events available');
                return ListView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 130),
                  itemCount: events.length,
                  itemBuilder: (ctx, i) {
                    final e = events[i];
                    return ClayCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      onTap: () => context.push('/attendance/scan'),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.name,
                          style: GoogleFonts.fredoka(fontWeight: FontWeight.bold, color: LitColors.bone, fontSize: 14),
                        ),
                        subtitle: Text(
                          e.venue ?? 'TBA',
                          style: GoogleFonts.plusJakartaSans(color: LitColors.ash, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.qr_code_scanner, color: LitColors.amber),
                      ),
                    );
                  },
                );
              },
            )
          : const Center(
              child: Text(
                'You do not have permission to mark attendance',
                style: TextStyle(color: LitColors.ash),
              ),
            ),
      floatingActionButton: role.canMarkAttendance
          ? Padding(
              padding: const EdgeInsets.only(bottom: 120, right: 8),
              child: ClayButton(
                width: 100,
                height: 48,
                borderRadius: 24,
                onPressed: () => context.push('/attendance/scan'),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 16),
                    SizedBox(width: 6),
                    Text('Scan'),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
