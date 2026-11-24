import 'package:supabase_flutter/supabase_flutter.dart';

class EmployeeStats {
  const EmployeeStats({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.roles,
    required this.uploadedItemsCount,
    required this.salesCount,
    required this.soldItemsCount,
    required this.totalSalesRevenue,
    required this.activeSalesDays,
    required this.dailyAvgRevenue,
    required this.dailyAvgSalesCount,
    this.canViewTeamStats = false,
  });

  final String userId;
  final String displayName;
  final String email;
  final List<String> roles;
  final int uploadedItemsCount;
  final int salesCount;
  final int soldItemsCount;
  final double totalSalesRevenue;
  final int activeSalesDays;
  final double dailyAvgRevenue;
  final double dailyAvgSalesCount;
  final bool canViewTeamStats;

  bool get isAdmin => roles.contains('admin');
  bool get isManager => roles.contains('manager');

  String get primaryRoleLabel {
    if (isAdmin) return 'Admin';
    if (isManager) return 'Manager';
    return 'Munkatárs';
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  factory EmployeeStats.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final roles = rawRoles is List
        ? rawRoles.map((entry) => entry.toString()).toList()
        : const <String>[];
    final email = json['email']?.toString().trim() ?? '';
    final rawName = json['display_name']?.toString().trim() ?? '';
    final displayName = rawName.isNotEmpty
        ? rawName
        : email.contains('@')
        ? email.split('@').first
        : (email.isNotEmpty ? email : 'Ismeretlen');

    return EmployeeStats(
      userId: json['user_id']?.toString() ?? '',
      displayName: displayName,
      email: email,
      roles: roles,
      uploadedItemsCount: _asInt(json['uploaded_items_count']),
      salesCount: _asInt(json['sales_count']),
      soldItemsCount: _asInt(json['sold_items_count']),
      totalSalesRevenue: _asDouble(json['total_sales_revenue']),
      activeSalesDays: _asInt(json['active_sales_days']),
      dailyAvgRevenue: _asDouble(json['daily_avg_revenue']),
      dailyAvgSalesCount: _asDouble(json['daily_avg_sales_count']),
      canViewTeamStats:
          json['can_view_team_stats'] == true ||
          roles.contains('admin') ||
          roles.contains('manager'),
    );
  }
}

abstract class EmployeeStatsGateway {
  Future<EmployeeStats> fetchMyStats();
  Future<List<EmployeeStats>> fetchAllEmployeeStats();
}

class SupabaseEmployeeStatsGateway implements EmployeeStatsGateway {
  const SupabaseEmployeeStatsGateway();

  @override
  Future<EmployeeStats> fetchMyStats() async {
    final response = await Supabase.instance.client.rpc(
      'get_my_employee_stats',
    );
    return EmployeeStats.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<List<EmployeeStats>> fetchAllEmployeeStats() async {
    final response = await Supabase.instance.client.rpc(
      'get_all_employee_stats',
    );
    return (response as List)
        .map((row) => EmployeeStats.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }
}
