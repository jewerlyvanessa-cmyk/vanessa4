import 'package:vanessa3/core/state/user_state.dart';

/// Generate nomor order custom: `{initials}C{8-digit}`.
String generateCustomOrderNumber(UserState userState) {
  String branchInitial = 'X';
  if (userState.branch.isNotEmpty && userState.branches.isNotEmpty) {
    try {
      final found = userState.branches.firstWhere(
        (b) => b['branch_id'].toString() == userState.branch,
      );
      final initials = found['initials'];
      if (initials != null && initials.toString().isNotEmpty) {
        branchInitial = initials.toString().toUpperCase();
      } else {
        final branchName = found['name'] ?? userState.branch;
        if (branchName.toString().isNotEmpty) {
          branchInitial = branchName.toString()[0].toUpperCase();
        }
      }
    } catch (_) {
      branchInitial = userState.branch.isNotEmpty
          ? userState.branch[0].toUpperCase()
          : 'X';
    }
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final uniqueNumber = (timestamp % 100000000).toString().padLeft(8, '0');
  return '${branchInitial}C$uniqueNumber';
}
