import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Periodic stream provider that ticks every 3 seconds.
/// Watching this provider inside any FutureProvider automatically re-fetches
/// and refreshes the data in the background without user interaction.
final autoRefreshProvider = StreamProvider<int>((ref) {
  return Stream.periodic(const Duration(seconds: 3), (count) => count);
});
