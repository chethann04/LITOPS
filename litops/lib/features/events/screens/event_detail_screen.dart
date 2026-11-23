import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/models.dart';
import '../../../core/enums/enums.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/utils/responsive.dart';


import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/widgets/top_notification.dart';
import '../../auth/providers/auth_provider.dart';
import 'events_screen.dart' show eventsListProvider;

final eventDetailProvider = StreamProvider.family<Event, String>((ref, eventId) async* {
  Future<Event?> fetchEvent() async {
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseTables.events)
          .select()
          .eq('id', eventId)
          .maybeSingle();
      if (res != null) {
        return Event.fromJson(res);
      }
    } catch (e) {
      debugPrint('⚠️ [EventDetail] fetch error: $e');
    }
    return null;
  }

  // 1. Initial immediate REST fetch
  final initial = await fetchEvent();
  if (initial != null) yield initial;

  // 2. Automatic refresh loop every 3 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
    final fresh = await fetchEvent();
    if (fresh != null) yield fresh;
  }
});

final eventRegistrationsCountProvider = StreamProvider.family<int, String>((ref, eventId) async* {
  Future<int> fetchCount() async {
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseTables.registrations)
          .select('id')
          .eq('event_id', eventId)
          .eq('is_cancelled', false);
      return (res as List).length;
    } catch (e) {
      debugPrint('⚠️ [EventRegistrations] fetch error: $e');
      return 0;
    }
  }

  // 1. Initial count
  yield await fetchCount();

  // 2. Continuous 3-second automatic refresh
  await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
    yield await fetchCount();
  }
});

final eventAttendanceCountProvider = StreamProvider.family<int, String>((ref, eventId) async* {
  Future<int> fetchCount() async {
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseTables.attendance)
          .select('id')
          .eq('event_id', eventId);
      return (res as List).length;
    } catch (e) {
      debugPrint('⚠️ [EventAttendance] fetch error: $e');
      return 0;
    }
  }

  // 1. Initial count
  yield await fetchCount();

  // 2. Continuous 3-second automatic refresh
  await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
    yield await fetchCount();
  }
});

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  EventStatus? _optimisticStatus;

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    final eventAsync = ref.watch(eventDetailProvider(eventId));
    final regCountAsync = ref.watch(eventRegistrationsCountProvider(eventId));
    final attCountAsync = ref.watch(eventAttendanceCountProvider(eventId));
    final roleConfig = ref.watch(roleConfigProvider);
    final isAllowedToRegister = roleConfig.canRegisterParticipants || (roleConfig.year >= 1 && roleConfig.year <= 4);
    final canEdit = roleConfig.canCreateEvents ||
                    roleConfig.canManageEvents ||
                    roleConfig.canManageEventSchedule ||
                    roleConfig.isAdmin ||
                    roleConfig.year == 4;

    return Scaffold(
      backgroundColor: LitColors.void_,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: LitColors.bone),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Event Details',
          style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: context.r.sp(16), color: LitColors.bone),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: LitColors.bone),
            onPressed: () {
              ref.invalidate(eventDetailProvider(eventId));
              ref.invalidate(eventRegistrationsCountProvider(eventId));
              ref.invalidate(eventAttendanceCountProvider(eventId));
            },
          ),
          if (roleConfig.canManageEvents)
            PopupMenuButton<String>(
              color: LitColors.clay,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: LitColors.border, width: 1.3),
              ),
              icon: const Icon(Icons.more_vert, color: LitColors.bone),
              onSelected: (value) async {
                if (value == 'command') {
                  context.push('/command-center/$eventId');
                } else if (value == 'report') {
                  context.push('/reports/$eventId');
                } else if (value == 'rounds') {
                  context.push('/rounds/$eventId');
                } else if (value == 'assign') {
                  final event = eventAsync.value;
                  if (event != null) {
                    context.push('/assignments', extra: event);
                  }
                } else if (value == 'edit') {
                  final event = eventAsync.value;
                  if (event != null) {
                    context.push('/events/$eventId/edit', extra: event);
                  }
                } else if (value == 'duplicate') {
                  _duplicateEvent(context, ref);
                } else if (value == 'archive') {
                  _archiveEvent(context, ref);
                } else if (value == 'delete') {
                  _deleteEvent(context, ref);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'command',
                  child: Row(
                    children: [
                      const Icon(Icons.monitor, color: LitColors.ash, size: 18),
                      const SizedBox(width: 12),
                      Text('Command Center', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rounds',
                  child: Row(
                    children: [
                      const Icon(Icons.layers, color: LitColors.ash, size: 18),
                      const SizedBox(width: 12),
                      Text('Rounds', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      const Icon(Icons.description, color: LitColors.ash, size: 18),
                      const SizedBox(width: 12),
                      Text('Generate Report', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                    ],
                  ),
                ),
                if (roleConfig.canAssignMembers)
                  PopupMenuItem(
                    value: 'assign',
                    child: Row(
                      children: [
                        const Icon(Icons.assignment_ind, color: LitColors.ash, size: 18),
                        const SizedBox(width: 12),
                        Text('Assign Crew', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                      ],
                    ),
                  ),
                if (roleConfig.canCreateEvents)
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, color: LitColors.ash, size: 18),
                        const SizedBox(width: 12),
                        Text('Edit Event', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Row(
                    children: [
                      const Icon(Icons.copy, color: LitColors.ash, size: 18),
                      const SizedBox(width: 12),
                      Text('Duplicate', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      const Icon(Icons.archive, color: LitColors.ash, size: 18),
                      const SizedBox(width: 12),
                      Text('Archive', style: GoogleFonts.plusJakartaSans(color: LitColors.bone)),
                    ],
                  ),
                ),
                if (roleConfig.isAdmin)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: LitColors.coral, size: 18),
                        const SizedBox(width: 12),
                        Text('Delete', style: GoogleFonts.plusJakartaSans(color: LitColors.coral)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: eventAsync.when(
        data: (event) {
          if (_optimisticStatus != null && event.status == _optimisticStatus) {
            _optimisticStatus = null;
          }
          final currentStatus = _optimisticStatus ?? event.status;
          final isOngoing = currentStatus == EventStatus.ongoing;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(eventDetailProvider(eventId));
                    ref.invalidate(eventRegistrationsCountProvider(eventId));
                    ref.invalidate(eventAttendanceCountProvider(eventId));
                    try {
                      await ref.read(eventDetailProvider(eventId).future);
                    } catch (_) {}
                  },
                  color: LitColors.ember,
                  backgroundColor: LitColors.clay,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: context.r.pageInsets,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category and Status chips row
                      Row(
                        children: [
                          CategoryChip(category: event.category.value),
                          SizedBox(width: context.r.w(8)),
                          if (roleConfig.canManageEvents)
                            Flexible(
                              child: GestureDetector(
                                onTap: () async {
                                  final newStatus = await showModalBottomSheet<EventStatus>(
                                    context: context,
                                    useRootNavigator: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) => ClayCard(
                                      color: LitColors.clay,
                                      padding: EdgeInsets.fromLTRB(context.r.w(16), context.r.h(16), context.r.w(16), context.r.h(16) + context.r.bottomSafeArea),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Change Status',
                                            style: GoogleFonts.fredoka(
                                              fontWeight: FontWeight.bold,
                                              fontSize: context.r.sp(16),
                                              color: LitColors.bone,
                                            ),
                                          ),
                                          SizedBox(height: context.r.h(16)),
                                          ...EventStatus.values.map((status) {
                                            return Material(
                                              color: Colors.transparent,
                                              child: ListTile(
                                                title: Text(status.label),
                                                leading: currentStatus == status
                                                    ? const Icon(Icons.check_circle, color: LitColors.moss)
                                                    : null,
                                                onTap: () {
                                                  Navigator.pop(ctx, status);
                                                },
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (newStatus != null && newStatus != currentStatus) {
                                    final previousStatus = currentStatus;
                                    setState(() => _optimisticStatus = newStatus);

                                    try {
                                      // 1. Try secure RPC first
                                      bool updatedViaRpc = false;
                                      try {
                                        await SupabaseConfig.client.rpc(
                                          'update_event_status',
                                          params: {
                                            'p_event_id': widget.eventId,
                                            'p_status': newStatus.value,
                                          },
                                        );
                                        updatedViaRpc = true;
                                      } catch (rpcErr) {
                                        debugPrint('⚠️ update_event_status RPC not available or failed ($rpcErr). Using direct update.');
                                      }

                                      // 2. Direct table update fallback
                                      if (!updatedViaRpc) {
                                        await SupabaseConfig.client
                                            .from(SupabaseTables.events)
                                            .update({
                                              'status': newStatus.value,
                                              'updated_at': DateTime.now().toIso8601String(),
                                            })
                                            .eq('id', widget.eventId);
                                      }

                                      // 3. Invalidate providers to synchronize state across the app
                                      ref.invalidate(eventDetailProvider(widget.eventId));
                                      ref.invalidate(eventsListProvider);
                                      if (mounted && context.mounted) {
                                        AppToast.updating(
                                          context,
                                          'Event status updated to ${newStatus.label}',
                                          title: 'Status Updated',
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('Error updating event status: $e');
                                      if (mounted) {
                                        setState(() => _optimisticStatus = previousStatus);
                                        if (context.mounted) {
                                          AppToast.failed(
                                            context,
                                            'Failed to update event status: $e',
                                            title: 'Status Update Failed',
                                          );
                                        }
                                      }
                                    }
                                  }
                                },
                                child: StatusChip(label: currentStatus.label),
                              ),
                            )
                          else
                            StatusChip(label: currentStatus.label),
                        ],
                      ),
                      SizedBox(height: context.r.h(12)),

                      // Wavy Poster Block
                      Container(
                        height: context.r.h(120),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [LitColors.clay3, LitColors.clay],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(context.r.radius(16)),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _getCategoryIcon(event.category),
                          color: LitColors.ember,
                          size: context.r.icon(38),
                        ),
                      ),
                      SizedBox(height: context.r.h(16)),

                      Text(
                        event.name,
                        style: GoogleFonts.fredoka(
                          fontSize: context.r.sp(20),
                          fontWeight: FontWeight.bold,
                          color: LitColors.bone,
                        ),
                      ),
                      SizedBox(height: context.r.h(8)),

                      // Tabs Layout
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTabItem(context, 'Overview', true, null),
                            _buildTabItem(context, 'Participants', false, () => context.push('/events/$eventId/participants', extra: event)),
                            _buildTabItem(context, 'Rounds', false, () => context.push('/rounds/$eventId')),
                            _buildTabItem(context, 'Results', false, () => context.push('/results/score/$eventId')),
                          ],
                        ),
                      ),
                      SizedBox(height: context.r.h(12)),

                      // Description
                      if (event.description != null)
                        Text(
                          event.description!,
                          style: GoogleFonts.plusJakartaSans(
                            color: LitColors.ash,
                            fontSize: context.r.sp(12),
                            height: 1.5,
                          ),
                        ),
                      SizedBox(height: context.r.h(16)),

                      // If ongoing or completed or results published - prominent Results Action Card in Overview
                      if (isOngoing || currentStatus == EventStatus.completed || currentStatus == EventStatus.resultsPublished)
                        Container(
                          margin: EdgeInsets.only(bottom: context.r.h(16)),
                          padding: EdgeInsets.all(context.r.w(14)),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF241C18), Color(0xFF191513)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(context.r.radius(14)),
                            border: Border.all(
                              color: currentStatus == EventStatus.resultsPublished
                                  ? LitColors.moss.withValues(alpha: 0.4)
                                  : LitColors.ember.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(context.r.w(10)),
                                decoration: BoxDecoration(
                                  color: currentStatus == EventStatus.resultsPublished
                                      ? LitColors.moss.withValues(alpha: 0.15)
                                      : LitColors.ember.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.emoji_events_rounded,
                                  color: currentStatus == EventStatus.resultsPublished ? LitColors.moss : LitColors.amber,
                                  size: context.r.icon(24),
                                ),
                              ),
                              SizedBox(width: context.r.w(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentStatus == EventStatus.resultsPublished
                                          ? 'Results Published'
                                          : 'Event Active: Ready for Results',
                                      style: GoogleFonts.fredoka(
                                        color: LitColors.bone,
                                        fontWeight: FontWeight.bold,
                                        fontSize: context.r.sp(14),
                                      ),
                                    ),
                                    Text(
                                      'Assign 1st, 2nd, 3rd, or custom positions with points to update leaderboard.',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: LitColors.ash,
                                        fontSize: context.r.sp(10.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: context.r.w(8)),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LitColors.ember,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: EdgeInsets.symmetric(horizontal: context.r.w(12), vertical: context.r.h(8)),
                                ),
                                onPressed: () => context.push('/results/score/$eventId'),
                                child: Text(
                                  currentStatus == EventStatus.resultsPublished ? 'Edit Results' : 'Publish Results',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: context.r.sp(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Details Grid
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: context.r.isSmall ? 1 : 2,
                        crossAxisSpacing: context.r.w(8),
                        mainAxisSpacing: context.r.h(8),
                        childAspectRatio: context.r.isSmall ? 3.5 : 2.2,
                        children: [
                          _buildDetailStat(
                            context,
                            'VENUE',
                            event.venue ?? 'TBD',
                            onEdit: canEdit ? () => _showEditVenueDialog(context, event) : null,
                            editIcon: Icons.edit_location_alt_rounded,
                          ),
                          _buildDetailStat(
                            context,
                            'DATE',
                            event.eventDate != null ? AppUtils.formatDate(event.eventDate!) : 'TBD',
                            onEdit: canEdit ? () => _showEditDateDialog(context, event) : null,
                            editIcon: Icons.edit_calendar_rounded,
                          ),
                          _buildDetailStat(context, 'REGISTRATIONS', '${regCountAsync.value ?? 0}'),
                          _buildDetailStat(context, 'ATTENDED', '${attCountAsync.value ?? 0}'),
                          _buildDetailStat(context, 'TEAM SIZE', '${event.teamSize}'),
                          _buildDetailStat(context, 'CAPACITY', event.capacity != null ? '${event.capacity}' : 'Unlimited'),
                        ],
                      ),
                      SizedBox(height: context.r.h(16)),

                      // Rules collapsible card
                      if (event.rules != null)
                        ClayInsetCard(
                          borderRadius: context.r.radius(14),
                          padding: EdgeInsets.symmetric(horizontal: context.r.w(14), vertical: context.r.h(12)),
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              title: Text(
                                'Rules & Eligibility',
                                style: GoogleFonts.plusJakartaSans(
                                  color: LitColors.bone,
                                  fontSize: context.r.sp(12),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              iconColor: LitColors.ash,
                              collapsedIconColor: LitColors.ash,
                              tilePadding: EdgeInsets.zero,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(top: context.r.h(8.0)),
                                  child: Text(
                                    event.rules!,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: LitColors.ash,
                                      fontSize: context.r.sp(11.5),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: context.r.h(16)),

                      // Operation quick link buttons
                      _buildOperationButton(
                        context,
                        'Waiting List',
                        Icons.hourglass_empty,
                        () => context.push('/waiting-list/$eventId'),
                      ),
                      _buildOperationButton(
                        context,
                        'Results Board',
                        Icons.emoji_events,
                        () => context.push('/results/score/$eventId'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

              // Bottom Register Bar
              Container(
                padding: EdgeInsets.all(context.r.w(16)),
                decoration: const BoxDecoration(
                  color: Color(0xFF141110),
                  border: Border(
                    top: BorderSide(color: Color(0xFF262220), width: 1.0),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (currentStatus == EventStatus.registrationOpen && isAllowedToRegister) ...[
                        ClayButton(
                          onPressed: () => context.go('/registration', extra: event),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_scanner, size: context.r.icon(16)),
                              SizedBox(width: context.r.w(8)),
                              const Text('Register Now'),
                            ],
                          ),
                        ),
                        SizedBox(height: context.r.h(8)),
                        Text(
                          'Waitlist enabled · Secured by Supabase Auth',
                          style: GoogleFonts.plusJakartaSans(
                            color: LitColors.ash,
                            fontSize: context.r.sp(10),
                          ),
                        ),
                      ],
                      if (isOngoing || currentStatus == EventStatus.completed || currentStatus == EventStatus.resultsPublished) ...[
                        if (roleConfig.canManageResults || roleConfig.canManageEvents) ...[
                          ClayButton(
                            onPressed: () => context.push('/results/score/$eventId'),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.emoji_events, size: context.r.icon(18), color: Colors.white),
                                SizedBox(width: context.r.w(8)),
                                Text(
                                  currentStatus == EventStatus.resultsPublished
                                      ? 'Edit & Re-Publish Results'
                                      : 'Publish Results',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: context.r.sp(13.5),
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: context.r.h(6)),
                          Text(
                            currentStatus == EventStatus.resultsPublished
                                ? 'Results published · Tap to edit positions or points'
                                : 'Event active · Assign 1st, 2nd, 3rd, or custom positions to publish',
                            style: GoogleFonts.plusJakartaSans(
                              color: currentStatus == EventStatus.resultsPublished ? LitColors.moss : LitColors.ash,
                              fontSize: context.r.sp(10),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () {
            ref.invalidate(eventDetailProvider(eventId));
            ref.invalidate(eventRegistrationsCountProvider(eventId));
            ref.invalidate(eventAttendanceCountProvider(eventId));
          },
        ),
      ),
    );
  }

  Widget _buildTabItem(BuildContext context, String text, bool active, VoidCallback? onTap) {
    final r = Responsive(context);
    final content = Container(
      margin: EdgeInsets.only(right: r.w(6)),
      padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(8)),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(colors: [LitColors.ember, LitColors.emberDark])
            : null,
        color: active ? null : LitColors.clay2,
        borderRadius: BorderRadius.circular(r.radius(12)),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          color: active ? const Color(0xFF1A0D05) : LitColors.ash,
          fontWeight: active ? FontWeight.bold : FontWeight.w600,
          fontSize: r.sp(10.5),
        ),
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }

  Future<void> _showEditVenueDialog(BuildContext context, Event event) async {
    final r = Responsive(context);
    final controller = TextEditingController(text: event.venue ?? '');
    final commonVenues = [
      'Auditorium',
      'Open Air Theatre (OAT)',
      'Main Stage',
      'Seminar Hall 1',
      'Seminar Hall 2',
      'Sports Complex',
      'Mechanical Block',
      'Library Hall',
    ];

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF191614),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(r.radius(20)),
                side: const BorderSide(color: Color(0xFF2C2623), width: 1.2),
              ),
              titlePadding: EdgeInsets.fromLTRB(r.w(20), r.h(20), r.w(20), r.h(10)),
              contentPadding: EdgeInsets.symmetric(horizontal: r.w(20)),
              actionsPadding: EdgeInsets.fromLTRB(r.w(16), r.h(12), r.w(16), r.h(16)),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(r.w(8)),
                    decoration: BoxDecoration(
                      color: LitColors.ember.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(r.radius(10)),
                    ),
                    child: Icon(Icons.location_on_rounded, color: LitColors.ember, size: r.icon(20)),
                  ),
                  SizedBox(width: r.w(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Venue',
                          style: GoogleFonts.fredoka(
                            fontSize: r.sp(16),
                            fontWeight: FontWeight.bold,
                            color: LitColors.bone,
                          ),
                        ),
                        Text(
                          event.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: r.sp(11.5),
                            color: LitColors.ash,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: r.h(8)),
                    Text(
                      'VENUE LOCATION',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.sp(10),
                        fontWeight: FontWeight.bold,
                        color: LitColors.ash,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: r.h(8)),
                    TextField(
                      controller: controller,
                      style: GoogleFonts.plusJakartaSans(color: LitColors.bone, fontSize: r.sp(13.5)),
                      decoration: InputDecoration(
                        hintText: 'Enter venue (e.g. Auditorium, OAT)',
                        hintStyle: TextStyle(color: LitColors.ash.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: LitColors.clay2,
                        prefixIcon: const Icon(Icons.place_outlined, color: LitColors.ember, size: 20),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: LitColors.ash, size: 18),
                                onPressed: () {
                                  controller.clear();
                                  setDialogState(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(r.radius(12)),
                          borderSide: BorderSide(color: LitColors.ember.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(r.radius(12)),
                          borderSide: const BorderSide(color: LitColors.clay3),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(r.radius(12)),
                          borderSide: const BorderSide(color: LitColors.ember, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    SizedBox(height: r.h(12)),
                    Text(
                      'Quick suggestions:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.sp(10.5),
                        color: LitColors.ash,
                      ),
                    ),
                    SizedBox(height: r.h(8)),
                    Wrap(
                      spacing: r.w(6),
                      runSpacing: r.h(6),
                      children: commonVenues.map((v) {
                        final isSelected = controller.text.trim() == v;
                        return ChoiceChip(
                          label: Text(v),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: r.sp(10.5),
                            color: isSelected ? Colors.white : LitColors.bone,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          selected: isSelected,
                          selectedColor: LitColors.ember,
                          backgroundColor: LitColors.clay2,
                          side: BorderSide(color: isSelected ? LitColors.ember : LitColors.clay3),
                          onSelected: (selected) {
                            controller.text = selected ? v : '';
                            setDialogState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: LitColors.ash,
                      fontWeight: FontWeight.w600,
                      fontSize: r.sp(13),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final newVenue = controller.text.trim();
                          setDialogState(() => saving = true);
                          try {
                            await SupabaseConfig.client
                                .from(SupabaseTables.events)
                                .update({
                                  'venue': newVenue.isEmpty ? null : newVenue,
                                  'updated_at': DateTime.now().toIso8601String(),
                                })
                                .eq('id', event.id);

                            ref.invalidate(eventDetailProvider(event.id));
                            ref.invalidate(eventsListProvider);

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (context.mounted) {
                              AppToast.success(
                                context,
                                'Venue updated to "${newVenue.isEmpty ? "TBD" : newVenue}"',
                                title: '📍 Venue Updated',
                              );
                            }
                          } catch (err) {
                            setDialogState(() => saving = false);
                            if (context.mounted) {
                              AppToast.failed(
                                context,
                                'Failed to update venue: $err',
                                title: 'Update Failed',
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LitColors.ember,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(horizontal: r.w(16), vertical: r.h(10)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Save Venue',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: r.sp(13),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDateDialog(BuildContext context, Event event) async {
    final r = Responsive(context);
    DateTime selectedDate = event.eventDate ?? DateTime.now();
    TimeOfDay? selectedTime;
    if (event.eventTime != null && event.eventTime!.isNotEmpty) {
      try {
        final parts = event.eventTime!.split(':');
        selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF191614),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(r.radius(20)),
                side: const BorderSide(color: Color(0xFF2C2623), width: 1.2),
              ),
              titlePadding: EdgeInsets.fromLTRB(r.w(20), r.h(20), r.w(20), r.h(10)),
              contentPadding: EdgeInsets.symmetric(horizontal: r.w(20)),
              actionsPadding: EdgeInsets.fromLTRB(r.w(16), r.h(12), r.w(16), r.h(16)),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(r.w(8)),
                    decoration: BoxDecoration(
                      color: LitColors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(r.radius(10)),
                    ),
                    child: Icon(Icons.calendar_month_rounded, color: LitColors.amber, size: r.icon(20)),
                  ),
                  SizedBox(width: r.w(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Date & Time',
                          style: GoogleFonts.fredoka(
                            fontSize: r.sp(16),
                            fontWeight: FontWeight.bold,
                            color: LitColors.bone,
                          ),
                        ),
                        Text(
                          event.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: r.sp(11.5),
                            color: LitColors.ash,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: r.h(8)),
                    Text(
                      'EVENT DATE',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.sp(10),
                        fontWeight: FontWeight.bold,
                        color: LitColors.ash,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: r.h(8)),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          useRootNavigator: true,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: LitColors.amber,
                                  onPrimary: Color(0xFF161312),
                                  surface: Color(0xFF1F1B19),
                                  onSurface: LitColors.bone,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF161312)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(r.radius(12)),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(12)),
                        decoration: BoxDecoration(
                          color: LitColors.clay2,
                          borderRadius: BorderRadius.circular(r.radius(12)),
                          border: Border.all(color: LitColors.clay3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event, color: LitColors.amber, size: 20),
                                SizedBox(width: r.w(10)),
                                Text(
                                  AppUtils.formatDate(selectedDate),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: LitColors.bone,
                                    fontSize: r.sp(13.5),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Change',
                              style: GoogleFonts.plusJakartaSans(
                                color: LitColors.amber,
                                fontSize: r.sp(12),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: r.h(16)),
                    Text(
                      'EVENT TIME (OPTIONAL)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.sp(10),
                        fontWeight: FontWeight.bold,
                        color: LitColors.ash,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: r.h(8)),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          useRootNavigator: true,
                          initialTime: selectedTime ?? const TimeOfDay(hour: 10, minute: 0),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: LitColors.amber,
                                  onPrimary: Color(0xFF161312),
                                  surface: Color(0xFF1F1B19),
                                  onSurface: LitColors.bone,
                                ),
                                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF161312)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(r.radius(12)),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(12)),
                        decoration: BoxDecoration(
                          color: LitColors.clay2,
                          borderRadius: BorderRadius.circular(r.radius(12)),
                          border: Border.all(color: LitColors.clay3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, color: LitColors.amber, size: 20),
                                SizedBox(width: r.w(10)),
                                Text(
                                  selectedTime != null
                                      ? selectedTime!.format(context)
                                      : (event.eventTime ?? 'Not specified'),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: selectedTime != null || event.eventTime != null ? LitColors.bone : LitColors.ash,
                                    fontSize: r.sp(13.5),
                                    fontWeight: selectedTime != null || event.eventTime != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              selectedTime != null || event.eventTime != null ? 'Change' : 'Set Time',
                              style: GoogleFonts.plusJakartaSans(
                                color: LitColors.amber,
                                fontSize: r.sp(12),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.plusJakartaSans(
                      color: LitColors.ash,
                      fontWeight: FontWeight.w600,
                      fontSize: r.sp(13),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            final dateStr = selectedDate.toIso8601String().split('T').first;
                            final timeStr = selectedTime != null
                                ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                : event.eventTime;

                            await SupabaseConfig.client
                                .from(SupabaseTables.events)
                                .update({
                                  'event_date': dateStr,
                                  'event_time': timeStr,
                                  'updated_at': DateTime.now().toIso8601String(),
                                })
                                .eq('id', event.id);

                            ref.invalidate(eventDetailProvider(event.id));
                            ref.invalidate(eventsListProvider);

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (context.mounted) {
                              AppToast.success(
                                context,
                                'Date updated to ${AppUtils.formatDate(selectedDate)}',
                                title: '📅 Date Updated',
                              );
                            }
                          } catch (err) {
                            setDialogState(() => saving = false);
                            if (context.mounted) {
                              AppToast.failed(
                                context,
                                'Failed to update date: $err',
                                title: 'Update Failed',
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LitColors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(horizontal: r.w(16), vertical: r.h(10)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF161312)),
                        )
                      : Text(
                          'Save Date & Time',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF161312),
                            fontWeight: FontWeight.bold,
                            fontSize: r.sp(13),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailStat(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onEdit,
    IconData? editIcon,
  }) {
    final r = Responsive(context);
    final cardContent = Container(
      padding: EdgeInsets.all(r.w(10)),
      decoration: BoxDecoration(
        color: LitColors.clay2,
        borderRadius: BorderRadius.circular(r.radius(14)),
        border: onEdit != null
            ? Border.all(color: LitColors.ember.withValues(alpha: 0.35), width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: const Offset(4, 4),
            blurRadius: 9,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.02),
            offset: const Offset(-2, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: r.sp(8.5),
                  fontWeight: FontWeight.bold,
                  color: LitColors.ash,
                  letterSpacing: 0.04,
                ),
              ),
              if (onEdit != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      editIcon ?? Icons.edit_rounded,
                      size: r.icon(11),
                      color: LitColors.ember,
                    ),
                    SizedBox(width: r.w(3)),
                    Text(
                      'Edit',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.sp(8.5),
                        fontWeight: FontWeight.bold,
                        color: LitColors.ember,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: r.h(2)),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.sp(12),
              fontWeight: FontWeight.bold,
              color: LitColors.bone,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onEdit != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(r.radius(14)),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }

  Widget _buildOperationButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.h(10)),
      child: ClayButton(
        isGhost: true,
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: r.icon(16)),
            SizedBox(width: r.w(8)),
            Text(label),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(EventCategory category) {
    switch (category) {
      case EventCategory.balwaan:
        return Icons.fitness_center;
      case EventCategory.buddhimaan:
        return Icons.lightbulb_outline;
      case EventCategory.darpan:
        return Icons.mic_none;
      case EventCategory.kalakruthi:
        return Icons.palette_outlined;
    }
  }

  Future<void> _duplicateEvent(BuildContext context, WidgetRef ref) async {
    final event = ref.read(eventDetailProvider(widget.eventId)).value;
    if (event == null) return;
    final client = SupabaseConfig.client;
    final userId = ref.read(authStateProvider).profile!.id;
    await client.from(SupabaseTables.events).insert({
      ...event.toJson(),
      'id': null,
      'title': '${event.name} (Copy)',
      'status': 'draft',
      'created_by': userId,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event duplicated')));
      ref.invalidate(eventDetailProvider(widget.eventId));
    }
  }

  Future<void> _archiveEvent(BuildContext context, WidgetRef ref) async {
    await SupabaseConfig.client.from(SupabaseTables.events).update({'status': 'archived'}).eq('id', widget.eventId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event archived')));
      ref.invalidate(eventDetailProvider(widget.eventId));
    }
  }

  Future<void> _deleteEvent(BuildContext context, WidgetRef ref) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Delete Event',
      message: 'Are you sure? This action cannot be undone.',
      confirmText: 'Delete',
      confirmColor: LitColors.coral,
      onConfirm: () {},
    );
    if (confirm == true) {
      await SupabaseConfig.client.from(SupabaseTables.events).delete().eq('id', widget.eventId);
      if (context.mounted) {
        context.go('/events');
      }
    }
  }
}
