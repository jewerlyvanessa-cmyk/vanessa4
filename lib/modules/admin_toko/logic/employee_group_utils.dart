class EmployeeGroup {
  const EmployeeGroup({
    required this.user,
    required this.assignments,
  });

  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> assignments;
}

abstract final class EmployeeGroupUtils {
  EmployeeGroupUtils._();

  static List<Map<String, dynamic>> asEmployeeMaps(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String userKeyForRow(Map<String, dynamic> row) {
    final userId =
        (row['user_id'] ?? row['id'] ?? row['userId'] ?? '').toString().trim();
    if (userId.isNotEmpty) return 'id:$userId';
    final username =
        (row['username'] ?? row['name'] ?? '').toString().trim().toLowerCase();
    return 'u:$username';
  }

  static List<EmployeeGroup> groupByUser(List<Map<String, dynamic>> rows) {
    final byUser = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = userKeyForRow(row);
      byUser.putIfAbsent(key, () => []);
      byUser[key]!.add(row);
    }

    final groups = byUser.entries.map((e) {
      final items = e.value;
      items.sort((a, b) {
        final au = (a['username'] ?? '').toString().length;
        final bu = (b['username'] ?? '').toString().length;
        return bu.compareTo(au);
      });
      return EmployeeGroup(user: items.first, assignments: items);
    }).toList();

    groups.sort((a, b) {
      final an = (a.user['username'] ?? '').toString().toLowerCase();
      final bn = (b.user['username'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    return groups;
  }

  static int countUniqueUsers(Iterable<Map<String, dynamic>> rows) {
    final keys = rows.map(userKeyForRow).where((k) => k != 'u:').toSet();
    return keys.length;
  }

  static int countUniqueUsersByStatus(
    List<Map<String, dynamic>> rows,
    String status,
  ) {
    final keys = <String>{};
    for (final row in rows) {
      if ((row['status'] ?? '').toString() == status) {
        keys.add(userKeyForRow(row));
      }
    }
    keys.remove('u:');
    return keys.length;
  }

  static int countUniqueUsersWithRole(
    List<Map<String, dynamic>> rows,
    String role,
  ) {
    final keys = <String>{};
    for (final row in rows) {
      if ((row['role'] ?? '').toString() == role) {
        keys.add(userKeyForRow(row));
      }
    }
    keys.remove('u:');
    return keys.length;
  }
}
