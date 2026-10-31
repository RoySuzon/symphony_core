import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/routing/app_routes.dart';
import '../../orders/presentation/providers/orders_providers.dart';

/// The modules of the dashboard.
///
/// The package filters them for the current user ([DashboardItem.access]):
/// sign in as `viewer@example.com`, `staff@example.com` or
/// `admin@example.com` to see different grids. The Orders badge is live
/// (number of pending orders, fetched from the backend).
final dashboardModulesProvider = Provider<List<DashboardItem>>(
  (ref) {
    final pending = ref.watch(pendingOrdersCountProvider).when(
          data: (count) => count,
          loading: () => null,
          error: (error, stackTrace) => null,
        );
    return buildDashboardModules(pendingOrders: pending);
  },
  name: 'dashboardModulesProvider',
);

/// Builds the module list; [pendingOrders] feeds the Orders badge.
List<DashboardItem> buildDashboardModules({int? pendingOrders}) {
  return <DashboardItem>[
    DashboardItem(
      id: 'orders',
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      description: 'Customer orders',
      route: AppRoutes.orders,
      access: const AccessRequirement(permissions: <String>{'orders.read'}),
      badge:
          pendingOrders == null || pendingOrders == 0 ? null : '$pendingOrders',
      color: const Color(0xFF00897B),
    ),
    const DashboardItem(
      id: 'reports',
      label: 'Reports',
      icon: Icons.insights_outlined,
      description: 'Sales indicators',
      route: AppRoutes.reports,
      access: AccessRequirement(permissions: <String>{'reports.view'}),
      color: Color(0xFF8E24AA),
    ),
    // A group: tapping it opens a nested submenu.
    const DashboardItem(
      id: 'admin',
      label: 'Admin',
      icon: Icons.admin_panel_settings_outlined,
      description: 'Users and audit log',
      access: AccessRequirement(roles: <String>{'admin'}),
      color: Color(0xFFE53935),
      children: <DashboardItem>[
        DashboardItem(
          id: 'admin.overview',
          label: 'Overview',
          icon: Icons.space_dashboard_outlined,
          route: AppRoutes.admin,
        ),
        DashboardItem(
          id: 'admin.users',
          label: 'Users',
          icon: Icons.manage_accounts_outlined,
          description: 'Accounts and roles',
          route: AppRoutes.adminUsers,
        ),
        DashboardItem(
          id: 'admin.audit',
          label: 'Audit log',
          icon: Icons.policy_outlined,
          description: 'Recorded by the backend',
          route: AppRoutes.auditLog,
        ),
      ],
    ),
    const DashboardItem(
      id: 'files',
      label: 'Files',
      icon: Icons.cloud_sync_outlined,
      description: 'Upload & download',
      route: AppRoutes.files,
      access: AccessRequirement.authenticated,
      color: Color(0xFF1E88E5),
    ),
    const DashboardItem(
      id: 'components',
      label: 'Components',
      // Custom icon: any widget, tinted through the tile's IconTheme.
      iconBuilder: _componentsIcon,
      description: 'UI showcase',
      route: AppRoutes.components,
      badge: 'New',
      color: Color(0xFFF4511E),
    ),
    const DashboardItem(
      id: 'inspector',
      label: 'API inspector',
      icon: Icons.manage_search_rounded,
      description: 'Captured HTTP calls',
      // A custom action instead of a route; '' shows a dot badge.
      onTap: _openInspector,
      badge: '',
      color: Color(0xFF546E7A),
    ),
    const DashboardItem(
      id: 'profile',
      label: 'Profile',
      icon: Icons.account_circle_outlined,
      description: 'Roles & permissions',
      route: AppRoutes.profile,
    ),
    const DashboardItem(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      description: 'Theme, environment, tools',
      route: AppRoutes.settings,
    ),
  ];
}

Widget _componentsIcon(BuildContext context) {
  final theme = IconTheme.of(context);
  final size = theme.size ?? 24;
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          child: Icon(Icons.crop_square_rounded, size: size * 0.7),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Icon(Icons.circle_outlined, size: size * 0.6),
        ),
      ],
    ),
  );
}

void _openInspector(BuildContext context) =>
    unawaited(showApiInspector(context));
