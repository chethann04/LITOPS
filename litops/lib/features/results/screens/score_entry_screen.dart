import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/enums/enums.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/top_notification.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_providers.dart';
import '../../events/screens/event_detail_screen.dart';
import '../../events/screens/events_screen.dart';
import '../../sarvottam/screens/leaderboard_screen.dart';
import 'results_screen.dart';

/// Represents a candidate (individual student or team) eligible for a position.
class CandidateItem {
  final String registrationId;
  final String? teamId;
  final String title;
  final String subtitle;
  final String? branch;
  final String? usn;

  const CandidateItem({
    required this.registrationId,
    this.teamId,
    required this.title,
    required this.subtitle,
    this.branch,
    this.usn,
  });
}

/// Dynamic position assignment entry.
class PositionEntry {
  final String id;
  String positionName;
  String positionKey;
  final int defaultPoints;
  String? selectedRegistrationId;
  final TextEditingController pointsController;

  PositionEntry({
    required this.id,
    required this.positionName,
    required this.positionKey,
    required this.defaultPoints,
    this.selectedRegistrationId,
    int? initialPoints,
  }) : pointsController = TextEditingController(
            text: (initialPoints ?? defaultPoints).toString());
}

class ScoreEntryScreen extends ConsumerStatefulWidget {
  final String eventId;
  const ScoreEntryScreen({super.key, required this.eventId});

  @override
  ConsumerState<ScoreEntryScreen> createState() => _ScoreEntryScreenState();
}

class _ScoreEntryScreenState extends ConsumerState<ScoreEntryScreen> {
  Event? _event;
  List<CandidateItem> _candidates = [];
  final List<PositionEntry> _positionEntries = [];
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEventAndRegistrations();
  }

  @override
  void dispose() {
    for (final entry in _positionEntries) {
      entry.pointsController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEventAndRegistrations() async {
    setState(() => _loading = true);
    try {
      // 1. Load event
      final eventData = await SupabaseConfig.client
          .from(SupabaseTables.events)
          .select()
          .eq('id', widget.eventId)
          .single();
      _event = Event.fromJson(eventData);

      // 2. Load registrations
      final regData = await SupabaseConfig.client
          .from(SupabaseTables.registrations)
          .select(
              'id, student_id, team_id, student_master(id, name, usn, branch), teams(id, team_name)')
          .eq('event_id', widget.eventId)
          .eq('is_cancelled', false);

      final rawList = List<Map<String, dynamic>>.from(regData as List);
      final candidates = <CandidateItem>[];
      final seenTeams = <String>{};

      for (final reg in rawList) {
        final team = reg['teams'] as Map<String, dynamic>?;
        final student = reg['student_master'] as Map<String, dynamic>?;
        final teamId = reg['team_id'] as String?;

        if (teamId != null && team != null) {
          if (!seenTeams.contains(teamId)) {
            seenTeams.add(teamId);
            final teamName = team['team_name'] as String? ?? 'Team';
            final rawBranch = student?['branch'] as String?;
            final usn = student?['usn'] as String?;
            final branch = (rawBranch != null && rawBranch.trim().isNotEmpty)
                ? AppUtils.mapUsnBranchToOfficial(rawBranch)
                : (usn != null && usn.trim().isNotEmpty
                    ? AppUtils.extractBranchFromUsn(usn)
                    : null);
            candidates.add(CandidateItem(
              registrationId: reg['id'] as String,
              teamId: teamId,
              title: teamName,
              subtitle:
                  'Team • ${student?['name'] ?? ''} (${branch ?? 'General'})',
              branch: branch,
              usn: usn,
            ));
          }
        } else {
          final name = student?['name'] as String? ?? 'Student';
          final usn = student?['usn'] as String? ?? '';
          final rawBranch = student?['branch'] as String?;
          final branch = (rawBranch != null && rawBranch.trim().isNotEmpty)
              ? AppUtils.mapUsnBranchToOfficial(rawBranch)
              : (usn.trim().isNotEmpty
                  ? AppUtils.extractBranchFromUsn(usn)
                  : null);
          candidates.add(CandidateItem(
            registrationId: reg['id'] as String,
            teamId: null,
            title: name,
            subtitle: '$usn • Branch: ${branch ?? 'N/A'}',
            branch: branch,
            usn: usn,
          ));
        }
      }

      _candidates = candidates;

      // 3. Load existing results if already published/saved
      final existingResults = await SupabaseConfig.client
          .from(SupabaseTables.results)
          .select('id, registration_id, team_id, position, score, remarks')
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: true);

      final existingList =
          List<Map<String, dynamic>>.from(existingResults as List);

      _positionEntries.clear();
      if (existingList.isNotEmpty) {
        for (int i = 0; i < existingList.length; i++) {
          final res = existingList[i];
          final posKey = res['position'] as String? ?? 'winner';
          final scoreNum = res['score'] as num?;
          final pts = scoreNum?.toInt() ?? _getDefaultPointsForIndex(i);
          final title =
              res['remarks'] as String? ?? _getDefaultTitleForIndex(i);

          _positionEntries.add(PositionEntry(
            id: 'pos_${DateTime.now().millisecondsSinceEpoch}_$i',
            positionName: title,
            positionKey: posKey,
            defaultPoints: pts,
            initialPoints: pts,
            selectedRegistrationId: res['registration_id'] as String?,
          ));
        }
      } else {
        // Default starting template: 1st, 2nd, 3rd (User can remove or add more)
        _positionEntries.addAll([
          PositionEntry(
            id: 'pos_1',
            positionName: '1st Place (Winner)',
            positionKey: 'winner',
            defaultPoints: 10,
          ),
          PositionEntry(
            id: 'pos_2',
            positionName: '2nd Place (Runner-Up)',
            positionKey: 'runner_up',
            defaultPoints: 7,
          ),
          PositionEntry(
            id: 'pos_3',
            positionName: '3rd Place (Second Runner-Up)',
            positionKey: 'second_runner_up',
            defaultPoints: 5,
          ),
        ]);
      }
    } catch (e) {
      debugPrint('Error loading event and registrations: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _getDefaultPointsForIndex(int index) {
    switch (index) {
      case 0:
        return 10;
      case 1:
        return 7;
      case 2:
        return 5;
      default:
        return 3;
    }
  }

  String _getDefaultTitleForIndex(int index) {
    switch (index) {
      case 0:
        return '1st Place (Winner)';
      case 1:
        return '2nd Place (Runner-Up)';
      case 2:
        return '3rd Place (Second Runner-Up)';
      case 3:
        return '4th Place';
      case 4:
        return '5th Place';
      default:
        return '${index + 1}th Place';
    }
  }

  String _getDefaultKeyForIndex(int index) {
    switch (index) {
      case 0:
        return 'winner';
      case 1:
        return 'runner_up';
      case 2:
        return 'second_runner_up';
      default:
        return 'second_runner_up';
    }
  }

  void _addPosition() {
    final nextIndex = _positionEntries.length;
    final newEntry = PositionEntry(
      id: 'pos_${DateTime.now().millisecondsSinceEpoch}',
      positionName: _getDefaultTitleForIndex(nextIndex),
      positionKey: _getDefaultKeyForIndex(nextIndex),
      defaultPoints: _getDefaultPointsForIndex(nextIndex),
    );
    setState(() {
      _positionEntries.add(newEntry);
    });
  }

  void _removePosition(int index) {
    setState(() {
      final removed = _positionEntries.removeAt(index);
      removed.pointsController.dispose();
    });
  }

  Future<void> _showCandidatePicker(PositionEntry entry) async {
    final searchController = TextEditingController();
    List<CandidateItem> filteredCandidates = List.from(_candidates);

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final r = Responsive(context);
            return Material(
              color: const Color(0xFF161312),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(r.radius(24))),
              clipBehavior: Clip.antiAlias,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                padding: EdgeInsets.fromLTRB(
                    r.w(16), r.h(16), r.w(16), r.h(16) + r.bottomSafeArea),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF2B2624), width: 1.5),
                  ),
                ),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: r.w(40),
                      height: r.h(4),
                      margin: EdgeInsets.only(bottom: r.h(14)),
                      decoration: BoxDecoration(
                        color: LitColors.ash.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(r.radius(2)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select ${entry.positionName}',
                        style: GoogleFonts.fredoka(
                          color: LitColors.bone,
                          fontSize: r.sp(16),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: LitColors.ash),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  SizedBox(height: r.h(10)),
                  TextField(
                    controller: searchController,
                    style: const TextStyle(color: LitColors.bone),
                    decoration: InputDecoration(
                      hintText: 'Search by name, USN, or branch...',
                      hintStyle:
                          const TextStyle(color: LitColors.ash, fontSize: 13),
                      prefixIcon: const Icon(Icons.search,
                          color: LitColors.ash, size: 20),
                      filled: true,
                      fillColor: const Color(0xFF1E1A18),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E2927)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E2927)),
                      ),
                    ),
                    onChanged: (query) {
                      final q = query.trim().toLowerCase();
                      setModalState(() {
                        if (q.isEmpty) {
                          filteredCandidates = List.from(_candidates);
                        } else {
                          filteredCandidates = _candidates.where((c) {
                            return c.title.toLowerCase().contains(q) ||
                                (c.usn?.toLowerCase().contains(q) ?? false) ||
                                (c.branch?.toLowerCase().contains(q) ??
                                    false) ||
                                c.subtitle.toLowerCase().contains(q);
                          }).toList();
                        }
                      });
                    },
                  ),
                  SizedBox(height: r.h(12)),
                  Expanded(
                    child: filteredCandidates.isEmpty
                        ? Center(
                            child: Text(
                              'No registered participants found',
                              style: GoogleFonts.plusJakartaSans(
                                  color: LitColors.ash),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredCandidates.length,
                            separatorBuilder: (_, __) => const Divider(
                                color: Color(0xFF24201E), height: 1),
                            itemBuilder: (ctx, i) {
                              final candidate = filteredCandidates[i];
                              final isSelected = entry.selectedRegistrationId ==
                                  candidate.registrationId;

                              // Check if selected by another position
                              final usedByOther = _positionEntries.any(
                                (p) =>
                                    p.id != entry.id &&
                                    p.selectedRegistrationId ==
                                        candidate.registrationId,
                              );

                              return Material(
                                color: Colors.transparent,
                                child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: r.w(8), vertical: r.h(2)),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isSelected
                                      ? LitColors.ember.withValues(alpha: 0.25)
                                      : const Color(0xFF26211F),
                                  child: Icon(
                                    candidate.teamId != null
                                        ? Icons.group
                                        : Icons.person,
                                    size: 18,
                                    color: isSelected
                                        ? LitColors.ember
                                        : LitColors.ash,
                                  ),
                                ),
                                title: Text(
                                  candidate.title,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: isSelected
                                        ? LitColors.ember
                                        : LitColors.bone,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: r.sp(13),
                                  ),
                                ),
                                subtitle: Text(
                                  candidate.subtitle,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: LitColors.ash,
                                    fontSize: r.sp(11),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (candidate.branch != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: LitColors.clay2,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          candidate.branch!,
                                          style: GoogleFonts.jetBrainsMono(
                                            color: LitColors.bone,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (usedByOther)
                                      Text(
                                        '(Assigned)',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: LitColors.amber,
                                          fontSize: 10,
                                        ),
                                      )
                                    else if (isSelected)
                                      const Icon(Icons.check_circle,
                                          color: LitColors.moss, size: 20),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    entry.selectedRegistrationId =
                                        candidate.registrationId;
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }

  Future<void> _publishResults() async {
    if (_positionEntries.isEmpty) {
      AppToast.warning(
        context,
        'Please add at least one position (Winner/Runner-up) before publishing!',
        title: 'No Positions',
      );
      return;
    }

    // Check each position has a selected candidate
    for (final pos in _positionEntries) {
      if (pos.selectedRegistrationId == null) {
        AppToast.warning(
          context,
          'Please select a participant for "${pos.positionName}" or remove it.',
          title: 'Participant Missing',
        );
        return;
      }

      final pts = int.tryParse(pos.pointsController.text.trim());
      if (pts == null || pts < 0) {
        AppToast.warning(
          context,
          'Please enter valid points (>= 0) for "${pos.positionName}".',
          title: 'Invalid Points',
        );
        return;
      }
    }

    // Check duplicate assignment
    final assignedIds =
        _positionEntries.map((p) => p.selectedRegistrationId!).toList();
    final uniqueIds = assignedIds.toSet();
    if (uniqueIds.length != assignedIds.length) {
      AppToast.warning(
        context,
        'The same participant cannot be assigned to multiple positions!',
        title: 'Duplicate Participant',
      );
      return;
    }

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1D1A18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2C2725)),
        ),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: LitColors.amber, size: 22),
            const SizedBox(width: 8),
            Text(
              'Publish Results?',
              style: GoogleFonts.fredoka(
                  color: LitColors.bone, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'This will publish ${_positionEntries.length} position(s) for "${_event?.name ?? 'Event'}", update the event status to Results Published, and credit Sarvottam Leaderboard points.',
          style: GoogleFonts.plusJakartaSans(
              color: LitColors.ash, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.plusJakartaSans(color: LitColors.ash)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: LitColors.ember,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Publish Now',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    final profile = ref.read(currentProfileProvider);

    try {
      // 1. Delete existing results & points for this event
      try {
        await SupabaseConfig.client
            .from(SupabaseTables.results)
            .delete()
            .eq('event_id', widget.eventId);
      } catch (delErr) {
        debugPrint('⚠️ Delete results warning: $delErr');
      }

      try {
        await SupabaseConfig.client
            .from(SupabaseTables.eventPoints)
            .delete()
            .eq('event_id', widget.eventId);
      } catch (ptsDelErr) {
        debugPrint('⚠️ Delete eventPoints warning: $ptsDelErr');
      }

      int insertedCount = 0;

      // 2. Insert/Upsert new results and points
      for (final entry in _positionEntries) {
        final candidate = _candidates.firstWhere(
          (c) => c.registrationId == entry.selectedRegistrationId,
        );

        final points = int.tryParse(entry.pointsController.text.trim()) ??
            entry.defaultPoints;

        // Upsert into results table to guarantee no unique constraint conflict
        await SupabaseConfig.client.from(SupabaseTables.results).upsert({
          'event_id': widget.eventId,
          'registration_id': candidate.registrationId,
          'team_id': candidate.teamId,
          'position': entry.positionKey,
          'score': points,
          'remarks': entry.positionName,
          'published_at': DateTime.now().toIso8601String(),
          'published_by': profile?.id,
        }, onConflict: 'event_id,registration_id');
        insertedCount++;

        // Insert into event_points table for leaderboard aggregation (safe guarded)
        try {
          final candidateBranch = candidate.branch ??
              (candidate.usn != null && candidate.usn!.trim().isNotEmpty
                  ? AppUtils.extractBranchFromUsn(candidate.usn!)
                  : null);
          if (candidateBranch != null && candidateBranch.trim().isNotEmpty) {
            final officialBranch =
                AppUtils.mapUsnBranchToOfficial(candidateBranch);
            await SupabaseConfig.client.from(SupabaseTables.eventPoints).insert({
              'event_id': widget.eventId,
              'branch': officialBranch,
              'student_id': null,
              'team_id': candidate.teamId,
              'points': points,
              'reason': '${_event?.name ?? "Event"} - ${entry.positionName}',
              'position': entry.positionKey,
              'allocated_by': profile?.id,
            });
          }
        } catch (ptsErr) {
          debugPrint('⚠️ eventPoints insert warning: $ptsErr');
        }
      }

      // 3. Update Event Status to results_published
      bool statusUpdatedViaRpc = false;
      try {
        await SupabaseConfig.client.rpc(
          'update_event_status',
          params: {
            'p_event_id': widget.eventId,
            'p_status': EventStatus.resultsPublished.value,
          },
        );
        statusUpdatedViaRpc = true;
      } catch (rpcErr) {
        debugPrint('⚠️ update_event_status RPC fallback: $rpcErr');
      }

      if (!statusUpdatedViaRpc) {
        try {
          await SupabaseConfig.client.from(SupabaseTables.events).update({
            'status': EventStatus.resultsPublished.value,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', widget.eventId);
        } catch (tableErr) {
          debugPrint('⚠️ event status update warning: $tableErr');
        }
      }

      // 4. Invalidate all relevant providers for real-time app-wide synchronization
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsListProvider);
      ref.invalidate(leaderboardProvider);
      ref.invalidate(departmentRankingsProvider);
      ref.invalidate(publishedEventsProvider);
      ref.invalidate(eventResultsProvider(widget.eventId));
      ref.invalidate(eventResultsWithDetailsProvider(widget.eventId));

      // 5. Send notifications to ALL 3rd and 4th year members (ONLY 3rd & 4th year members)
      final eventTitle = _event?.name ?? 'Event';
      final winnersSummary = <String>[];
      for (final entry in _positionEntries) {
        CandidateItem? cand;
        for (final c in _candidates) {
          if (c.registrationId == entry.selectedRegistrationId) {
            cand = c;
            break;
          }
        }
        if (cand != null) {
          final branchStr = (cand.branch != null && cand.branch!.isNotEmpty)
              ? ' (${cand.branch})'
              : '';
          winnersSummary.add('${entry.positionName}: ${cand.title}$branchStr');
        }
      }
      final summary = winnersSummary.isNotEmpty
          ? winnersSummary.take(3).join('\n')
          : null;

      try {
        await NotificationService().notifySeniorMembersOnResultsPublished(
          eventId: widget.eventId,
          eventName: eventTitle,
          publisherUserId: profile?.id,
          summaryText: summary,
        );
      } catch (notifErr) {
        debugPrint('⚠️ Error sending results published notification: $notifErr');
      }

      if (mounted) {
        AppToast.completed(
          context,
          'Published $insertedCount position(s)! Leaderboard updated.',
          title: 'Results Published 🎉',
        );
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      debugPrint('Error publishing results: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        AppToast.failed(
          context,
          'Error publishing results: $e',
          title: 'Publish Failed',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildMedalBadge(int index, Responsive r) {
    String medal = '🏅';
    Color medalColor = LitColors.amber;
    if (index == 0) {
      medal = '🥇';
      medalColor = const Color(0xFFFFD700);
    } else if (index == 1) {
      medal = '🥈';
      medalColor = const Color(0xFFC0C0C0);
    } else if (index == 2) {
      medal = '🥉';
      medalColor = const Color(0xFFCD7F32);
    }

    return Container(
      width: r.w(36),
      height: r.w(36),
      decoration: BoxDecoration(
        color: medalColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border:
            Border.all(color: medalColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Center(
        child: Text(medal, style: TextStyle(fontSize: r.sp(18))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider);
    final r = Responsive(context);

    if (!role.canManageResults) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: LitColors.bone),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Access Denied',
              style: TextStyle(
                  color: LitColors.bone, fontWeight: FontWeight.bold)),
        ),
        body: const Center(
          child: EmptyView(
            icon: Icons.lock_outline,
            title: 'Not Authorized',
            subtitle: 'You do not have permission to publish or edit results.',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E0C0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141110),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: LitColors.bone),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _event?.name ?? 'Result Entry',
              style: GoogleFonts.fredoka(
                color: LitColors.bone,
                fontWeight: FontWeight.bold,
                fontSize: r.sp(16),
              ),
            ),
            Text(
              'Assign positions & points',
              style: GoogleFonts.plusJakartaSans(
                color: LitColors.ash,
                fontSize: r.sp(11),
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading && _positionEntries.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: r.w(8)),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _publishResults,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 14, color: Colors.white),
                label: Text(
                  _saving ? 'Publishing...' : 'Publish',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: r.sp(12),
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LitColors.ember,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.symmetric(
                      horizontal: r.w(12), vertical: r.h(8)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _candidates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_off,
                            color: LitColors.ash, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'No Registrations Found',
                          style: GoogleFonts.fredoka(
                            color: LitColors.bone,
                            fontSize: r.sp(16),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'There are no active participants registered for this event yet.',
                          style: GoogleFonts.plusJakartaSans(
                              color: LitColors.ash, fontSize: r.sp(12)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Header info card
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.fromLTRB(
                          r.w(14), r.h(12), r.w(14), r.h(6)),
                      padding: EdgeInsets.symmetric(
                          horizontal: r.w(14), vertical: r.h(12)),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171312),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF282220), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.military_tech_rounded,
                              color: LitColors.amber, size: r.icon(22)),
                          SizedBox(width: r.w(10)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customizable Results (${_positionEntries.length} Positions)',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: LitColors.bone,
                                    fontWeight: FontWeight.bold,
                                    fontSize: r.sp(12.5),
                                  ),
                                ),
                                Text(
                                  'Assign 1st, 2nd, 3rd, or any number of positions with custom points.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: LitColors.ash,
                                    fontSize: r.sp(10.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addPosition,
                            icon: const Icon(Icons.add,
                                size: 16, color: LitColors.ember),
                            label: Text(
                              'Add',
                              style: GoogleFonts.plusJakartaSans(
                                color: LitColors.ember,
                                fontWeight: FontWeight.bold,
                                fontSize: r.sp(11.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Position Entries List
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                            r.w(14), r.h(6), r.w(14), r.h(80)),
                        itemCount: _positionEntries.length,
                        itemBuilder: (ctx, i) {
                          final entry = _positionEntries[i];
                          final assignedCandidate = entry
                                      .selectedRegistrationId ==
                                  null
                              ? null
                              : _candidates.cast<CandidateItem?>().firstWhere(
                                    (c) =>
                                        c?.registrationId ==
                                        entry.selectedRegistrationId,
                                    orElse: () => null,
                                  );

                          return Container(
                            margin: EdgeInsets.only(bottom: r.h(12)),
                            decoration: BoxDecoration(
                              color: const Color(0xFF191614),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: assignedCandidate != null
                                    ? LitColors.ember.withValues(alpha: 0.35)
                                    : const Color(0xFF282321),
                                width: 1.2,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(r.w(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Row with Medal, Position Title & Delete Button
                                  Row(
                                    children: [
                                      _buildMedalBadge(i, r),
                                      SizedBox(width: r.w(10)),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.positionName,
                                              style: GoogleFonts.fredoka(
                                                color: LitColors.bone,
                                                fontWeight: FontWeight.bold,
                                                fontSize: r.sp(14),
                                              ),
                                            ),
                                            Text(
                                              'Rank #${i + 1}',
                                              style: GoogleFonts.jetBrainsMono(
                                                color: LitColors.ash,
                                                fontSize: r.sp(10),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Custom Points Input
                                      SizedBox(
                                        width: r.w(90),
                                        child: TextFormField(
                                          controller: entry.pointsController,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.jetBrainsMono(
                                            color: LitColors.amber,
                                            fontWeight: FontWeight.bold,
                                            fontSize: r.sp(14),
                                          ),
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            labelText: 'Points',
                                            labelStyle:
                                                GoogleFonts.plusJakartaSans(
                                              color: LitColors.ash,
                                              fontSize: r.sp(10),
                                            ),
                                            suffixText: 'pts',
                                            suffixStyle:
                                                GoogleFonts.jetBrainsMono(
                                              color: LitColors.ash,
                                              fontSize: r.sp(9),
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: r.w(8),
                                              vertical: r.h(8),
                                            ),
                                            filled: true,
                                            fillColor: const Color(0xFF221E1C),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFF332B28)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFF332B28)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: LitColors.ember),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: r.w(6)),
                                      // Delete Position Button
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: LitColors.ash, size: 20),
                                        splashRadius: 18,
                                        onPressed: () => _removePosition(i),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: r.h(12)),

                                  // Participant Selector Box
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _showCandidatePicker(entry),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: r.w(12),
                                          vertical: r.h(10)),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF141110),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: assignedCandidate != null
                                              ? LitColors.moss
                                                  .withValues(alpha: 0.4)
                                              : const Color(0xFF2E2724),
                                          width: 1,
                                        ),
                                      ),
                                      child: assignedCandidate == null
                                          ? Row(
                                              children: [
                                                const Icon(
                                                    Icons
                                                        .person_add_alt_1_outlined,
                                                    color: LitColors.ash,
                                                    size: 18),
                                                SizedBox(width: r.w(8)),
                                                Expanded(
                                                  child: Text(
                                                    'Tap to select participant or team...',
                                                    style: GoogleFonts
                                                        .plusJakartaSans(
                                                      color: LitColors.ash,
                                                      fontSize: r.sp(12),
                                                    ),
                                                  ),
                                                ),
                                                const Icon(
                                                    Icons.arrow_drop_down,
                                                    color: LitColors.ash),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                Icon(
                                                  assignedCandidate.teamId !=
                                                          null
                                                      ? Icons.group
                                                      : Icons.person,
                                                  color: LitColors.moss,
                                                  size: 18,
                                                ),
                                                SizedBox(width: r.w(8)),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        assignedCandidate.title,
                                                        style: GoogleFonts
                                                            .plusJakartaSans(
                                                          color: LitColors.bone,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: r.sp(13),
                                                        ),
                                                      ),
                                                      Text(
                                                        assignedCandidate
                                                            .subtitle,
                                                        style: GoogleFonts
                                                            .plusJakartaSans(
                                                          color: LitColors.ash,
                                                          fontSize: r.sp(11),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (assignedCandidate.branch !=
                                                    null)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    margin:
                                                        const EdgeInsets.only(
                                                            right: 6),
                                                    decoration: BoxDecoration(
                                                      color: LitColors.ember
                                                          .withValues(
                                                              alpha: 0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: Border.all(
                                                          color: LitColors.ember
                                                              .withValues(
                                                                  alpha: 0.3)),
                                                    ),
                                                    child: Text(
                                                      assignedCandidate.branch!,
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        color: LitColors.ember,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                const Icon(Icons.edit,
                                                    color: LitColors.ash,
                                                    size: 16),
                                              ],
                                            ),
                                    ),
                                  ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _candidates.isEmpty
          ? null
          : Container(
              height: r.h(70) + r.bottomSafeArea,
              padding: EdgeInsets.fromLTRB(r.w(14), r.h(10), r.w(14), r.h(10) + r.bottomSafeArea),
              decoration: const BoxDecoration(
                color: Color(0xFF141110),
                border: Border(
                  top: BorderSide(color: Color(0xFF262220), width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: r.h(48),
                      child: OutlinedButton.icon(
                        onPressed: _addPosition,
                        icon: const Icon(Icons.add_rounded, size: 16, color: LitColors.bone),
                        label: Text(
                          'Add Position',
                          style: GoogleFonts.plusJakartaSans(
                            color: LitColors.bone,
                            fontWeight: FontWeight.bold,
                            fontSize: r.sp(12),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF332B28)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: r.w(10)),
                  Expanded(
                    flex: 3,
                    child: ClayButton(
                      height: r.h(48),
                      onPressed: _saving ? null : _publishResults,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_saving)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else ...[
                            Icon(Icons.emoji_events_rounded, size: r.icon(16), color: Colors.white),
                            SizedBox(width: r.w(6)),
                          ],
                          Text(
                            _saving ? 'Publishing...' : 'Publish Results',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: r.sp(13),
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
