import 'dart:async';

import 'package:flutter/material.dart';
import '../models/center_model.dart';
import '../models/donation_summary.dart';
import '../models/notification_item.dart';
import '../models/user_model.dart';
import '../services/dashboard_service.dart';
import 'admin_accounts_page.dart';
import 'center_detail_page.dart';
import 'center_page.dart';
import 'donations_page.dart';
import '../config/supabase_config.dart';

enum DashboardSection { dashboard, centers, distribution, accountManagement }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashboardService _dashboardService = DashboardService();
  DashboardSection _selectedSection = DashboardSection.dashboard;
  bool _isLoading = false;
  Map<String, int> _stats = {
  'patients': 0,
  'appointments': 0,
  'centers': 0,   // ✅ clinics → centers
  'donations': 0,
  };

  List<CenterModel> _centers = [];
  List<NotificationItem> _notifications = [];
  List<DonationSummary> _donationTotals = [];
  Timer? _notificationTimer;
  Timer? _clockTimer;

 @override
  void initState() {
  super.initState();

  SupabaseConfig.client
      .from('clinics')
      .stream(primaryKey: ['id'])
      .listen((data) {
    if (!mounted) return;

    setState(() {
      _centers = data
          .map((e) => CenterModel.fromJson(e))
          .toList();
    });
  });

  _notificationTimer = Timer.periodic(const Duration(seconds: 12), (_) {
    _refreshNotifications();
  });

  _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (mounted) setState(() {});
  });
}
  
  
  @override
  void dispose() {
  _notificationTimer?.cancel();
  _clockTimer?.cancel(); // ✅ before super
  super.dispose();
}

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = false;
    });

     final messenger = ScaffoldMessenger.of(context);
    try {
    final stats = await _dashboardService.fetchOverviewStats();

    print('Stats from service: $stats'); // ✅ dito mo ilalagay

    final centers = await _dashboardService.fetchCenters();
    final notifications = await _dashboardService.fetchNotifications();
    final donationTotals = await _dashboardService.fetchDonationSummary();

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _centers = centers;
        _notifications = notifications;
        _donationTotals = donationTotals;
      });
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Unable to load dashboard data. ${error.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

 
  Future<void> _refreshNotifications() async {
    try {
      final notifications = await _dashboardService.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
      });
    } catch (_) {
      // ignore: avoid_print
      print('Notification refresh failed.');
    }
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }
  
  @override
  Widget build(BuildContext context) {
    final user = ModalRoute.of(context)?.settings.arguments as UserModel?;

    final dashboardBody = Container(
      color: const Color(0xFFF5F7FA),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _buildContent(user),
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 280,
            color: const Color(0xFF174E71),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                        child: const Icon(
                          Icons.local_hospital,
                          color: Color(0xFF174E71),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CureNurture\nSuper Admin Panel',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _SidebarItem(
                  label: 'Dashboard',
                  icon: Icons.dashboard,
                  selected: _selectedSection == DashboardSection.dashboard,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.dashboard;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Centers',
                  icon: Icons.location_city,
                  selected: _selectedSection == DashboardSection.centers,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.centers;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Distribute Donation',
                  icon: Icons.volunteer_activism,
                  selected: _selectedSection == DashboardSection.distribution,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.distribution;
                    });
                  },
                ),
                _SidebarItem(
                  label: 'Account Management',
                  icon: Icons.manage_accounts,
                  selected: _selectedSection == DashboardSection.accountManagement,
                  onTap: () {
                    setState(() {
                      _selectedSection = DashboardSection.accountManagement;
                    });
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Log out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF174E71),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                dashboardBody,
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.72),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCenterDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final machinesController = TextEditingController();
    final slotsController = TextEditingController();
    final hoursController = TextEditingController(text: '7:00 AM - 5:00 PM');
    final contactController = TextEditingController();
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Center'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField(controller: nameController, label: 'Center Name'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: addressController, label: 'Address'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: machinesController, label: 'Number of Machines', keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    _buildTextField(controller: slotsController, label: 'Available Slots', keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    _buildTextField(controller: hoursController, label: 'Operating Hours'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: contactController, label: 'Contact Number', keyboardType: TextInputType.phone),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          isSaving = true;
                        });
                        try {
                          await _dashboardService.createCenter(
                            name: nameController.text.trim(),
                            address: addressController.text.trim(),
                            city: 'Unknown',
                            requirements: ['N/A'],
                            latitude: 0.0,
                            longitude: 0.0,
                            slotAvailable: int.tryParse(slotsController.text.trim()) ?? 0,
                            machines: int.tryParse(machinesController.text.trim()) ?? 0, // ✅ ADD
                            shifts: 2, // ✅ ADD
                            operatingHours: hoursController.text.trim(),
                            contactNumber: contactController.text.trim(),
                          );

                          Navigator.pop(context);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Center added successfully.')),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Unable to add center: ${error.toString()}')),
                          );
                        } finally {
                          setDialogState(() {
                            isSaving = false;
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: isSaving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _showExportDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Export Reports'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: const Text('Choose the data type you want to export and select PDF or CSV format.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reports export started.')));
              },
              child: const Text('Export CSV'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: (value) => (value == null || value.isEmpty) ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildContent(UserModel? user) {
    switch (_selectedSection) {
      case DashboardSection.centers:
        return ClinicsPage(onUpdated: () {});
      case DashboardSection.distribution:
        return const DonationsPage();
      case DashboardSection.accountManagement:
        return const AccountManagementPage();
      case DashboardSection.dashboard:
        return _buildDashboardHome(user);
    } 
  }

  Widget _buildDashboardHome(UserModel? user) {
  final width = MediaQuery.of(context).size.width;

  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SizedBox(height: 24),

        // 🔥 1. TOP — CAPACITY (PRIORITY)
        _buildCapacityOverview(width),

        const SizedBox(height: 20),

        // 🔥 2. MIDDLE — DONATIONS + NOTIFICATIONS
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildOverviewCards(1)),
            const SizedBox(width: 16),
            Expanded(child: _buildNotificationsPanel()),
          ],
        ),

        const SizedBox(height: 20),

        // 🔥 3. BOTTOM — CENTER GRID (CENTERED)
        Center(
          child: SizedBox(
            width: 1100,
            child: _buildCenterGrid(width),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildOverviewCards(int columns) {
  final stats = [
    _OverviewStat(
      label: 'Total Donations',
      value: '₱${_stats['donations'] ?? 0}',
      icon: Icons.volunteer_activism_outlined,
    ),
  ];

  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: stats.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 3.2,
    ),
    itemBuilder: (context, index) => stats[index],
  );
}

 Widget _buildCapacityOverview(double width) {
  final crossAxisCount = width > 1400 ? 3 : width > 1100 ? 2 : 1;

  final centers = _centers;

  if (centers.isEmpty) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Center(child: Text('No capacity data available yet.')),
    );
  }

  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Center Capacity Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          itemCount: centers.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.4,
          ),
          itemBuilder: (context, index) =>
              _buildCapacityCard(centers[index]),
        ),
      ],
    ),
  );
}

Widget _buildCapacityCard(CenterModel center) {
  final machine = center.machines;
  final shifts = center.shifts;
  final slots = center.availableSlots;

  final totalCapacity = machine * shifts;

  final usedSlots = (totalCapacity - slots).clamp(0, totalCapacity);

  final occupancy = totalCapacity > 0
      ? (usedSlots / totalCapacity) * 100
      : 0.0;

  final isOpen = _isOpenNow(center.operatingHours);

  final dbStatus = center.status.toLowerCase();

  // ✅ USE GLOBAL COLOR FUNCTION
  final statusColor = _statusColor(dbStatus);

  String statusLabel;

  if (totalCapacity == 0) {
    statusLabel = 'No Data';
  } else if (!isOpen) {
    statusLabel = 'Closed';
  } else if (occupancy > 100) {
    statusLabel = 'Overloaded';
  } else {
    switch (dbStatus) {
      case 'maintenance':
        statusLabel = 'Maintenance';
        break;
      case 'full':
        statusLabel = 'Full';
        break;
      case 'busy':
        statusLabel = 'Busy';
        break;
      case 'open':
      default:
        statusLabel = 'Open';
    }
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 🔹 HEADER
        Row(
          children: [
            Expanded(
              child: Text(
                center.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),

            // 🔥 STATUS CHIP (IMPROVED)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 🔥 PROGRESS BAR (ROUNDED)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (occupancy / 100).clamp(0.0, 1.0),
            color: statusColor,
            backgroundColor: statusColor.withOpacity(0.15),
            minHeight: 8,
          ),
        ),

        const SizedBox(height: 8),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // 🔥 MAIN OCCUPANCY TEXT
            Text(
              '${occupancy.toStringAsFixed(0)}% Occupied • Slots left: $slots',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),

            const SizedBox(height: 4),

            // 🟢 LABEL (Stable / Busy / Critical)
            Text(
              _occupancyLabel(occupancy),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),

            const SizedBox(height: 4),

            // ⏰ OPEN/CLOSE
            Text(
              _openCloseText(center.operatingHours),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
 Widget _buildNotificationsPanel() {
  final notifications = _notifications.isEmpty
      ? [
          NotificationItem(
            id: 'placeholder1',
            message: 'No recent alerts yet. Data will appear as events arrive.',
            timestamp: DateTime.now(),
            source: 'System',
          ),
        ]
      : _notifications;

  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alerts & Notifications (${notifications.length})', // ✅ badge counter
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ...notifications.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6, right: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1F719F),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.message,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('${item.source} · ${_formatTimeAgo(item.timestamp)}',
                            style: const TextStyle(
                                color: Color(0xFF6C7A89), fontSize: 13)),
                        
                      ],
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 8),
       TextButton(
        onPressed: () {
       _refreshNotifications(); // ✅ call async function inside a void callback
      },
      child: const Text('Refresh Alerts'),
    )

      ],
    ),
  );
}

Widget _buildCenterGrid(double width) {
  final crossAxisCount = width > 1400 ? 3 : width > 1100 ? 2 : 1;
  final centers = _centers;

  if (centers.isEmpty) {
    return const Center(child: Text('No centers available.'));
  }

  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Valenzuela Clinics and Centers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: centers.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.3,
          ),
          itemBuilder: (context, index) {
            final center = centers[index]; // ✅ IMPORTANT

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CenterDetailPage(center: center),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      center.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Text(
                          center.operatingHours,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            center.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _miniStat("Machines", center.machines.toString()),
                        _miniStat("Slots", center.availableSlots.toString()),
                        _miniStat("Shifts", center.shifts.toString()),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}
Widget _miniStat(String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF9CA3AF),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
  String _occupancyLabel(double occupancy) {
  if (occupancy <= 50) return 'Stable';
  if (occupancy <= 85) return 'Busy';
  if (occupancy <= 100) return 'Critical';
  return 'Overloaded'; // 🔥 NEW
}
  bool _isOpenNow(String? hours) {
  if (hours == null || !hours.contains('-')) return false;

  try {
    final parts = hours.split('-');
    final open = _parseSimpleTime(parts[0]);
    final close = _parseSimpleTime(parts[1]);

    final now = TimeOfDay.now();

    final nowMin = now.hour * 60 + now.minute;
    final openMin = open.hour * 60 + open.minute;
    final closeMin = close.hour * 60 + close.minute;

    return nowMin >= openMin && nowMin <= closeMin;
  } catch (e) {
    return false;
  } 
}
TimeOfDay _parseSimpleTime(String timeStr) {
  final cleaned = timeStr.trim().toUpperCase();

  final regex = RegExp(r'(\d{1,2}):?(\d{2})?\s*(AM|PM)');
  final match = regex.firstMatch(cleaned);

  if (match == null) throw Exception("Invalid time format");

  int hour = int.parse(match.group(1)!);
  int minute = int.parse(match.group(2) ?? '0');
  String period = match.group(3)!;

  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;

  return TimeOfDay(hour: hour, minute: minute);
}
String _openCloseText(String? hours) {
  if (hours == null || !hours.contains('-')) return '';

  final parts = hours.split('-');

  final now = TimeOfDay.now();
  final open = _parseSimpleTime(parts[0]);
  final close = _parseSimpleTime(parts[1]);

  final nowMin = now.hour * 60 + now.minute;
  final openMin = open.hour * 60 + open.minute;
  final closeMin = close.hour * 60 + close.minute;

  if (nowMin >= openMin && nowMin <= closeMin) {
    return 'Closes at ${parts[1].trim()}';
  } else {
    return 'Opens at ${parts[0].trim()}';
  }
} 
String _formatTimeAgo(DateTime timestamp) {
  final difference = DateTime.now().difference(timestamp);

  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} hr ago';
  return '${difference.inDays} day(s) ago';
}
Color _statusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'open':
      return const Color(0xFF1F9D55);
    case 'busy':
      return const Color(0xFFED8F12);
    case 'full':
      return const Color(0xFFB91C1C);
    case 'maintenance':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF2563EB);
  }
}
}
class _OverviewStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _OverviewStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    
    return Container(
      decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),

      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1F719F), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF6B7D8F), fontSize: 14)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
}

class _ActionCard extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6FBFF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
               decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(description, style: const TextStyle(color: Color(0xFF5E7385), fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF0F719F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicStat extends StatelessWidget {
  final String label;
  final String value;

  const _ClinicStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF5E7385))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: selected 
            ? const Color(0xFF1F719F) // ✅ highlight
            : Colors.transparent,     // ✅ FIX (wala nang white box)
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
  borderRadius: BorderRadius.circular(20),
  onTap: onTap,
  child: ListTile(
    leading: Icon(
      icon,
      color: selected ? Colors.white : Colors.white70,
    ),
    title: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  ),
),
    );
  }
}