import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/center_model.dart';
import '../services/dashboard_service.dart';
import '../config/supabase_config.dart';
import '../services/profile_service.dart';
import 'dart:ui';

bool isCenterOpenByOperatingHours(String? operatingHours) {
  if (operatingHours == null || operatingHours.trim().isEmpty) return false;

  try {
    final normalized = operatingHours
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s+to\s+', caseSensitive: false), '-')
        .replaceAll(RegExp(r'\s+until\s+', caseSensitive: false), '-');

    final parts = normalized.split('-');
    if (parts.length < 2) return false;

    final openTime = _parseOperatingTime(parts[0]);
    final closeTime = _parseOperatingTime(parts[1]);
    final now = TimeOfDay.now();

    final nowMinutes = (now.hour * 60) + now.minute;
    final openMinutes = (openTime.hour * 60) + openTime.minute;
    final closeMinutes = (closeTime.hour * 60) + closeTime.minute;

    if (openMinutes == closeMinutes) return true;

    // Handles overnight schedules like 8:00 PM - 6:00 AM.
    if (closeMinutes < openMinutes) {
      return nowMinutes >= openMinutes || nowMinutes <= closeMinutes;
    }

    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  } catch (_) {
    return false;
  }
}

TimeOfDay _parseOperatingTime(String value) {
  final cleaned = value.trim().toUpperCase();
  final regex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?');
  final match = regex.firstMatch(cleaned);

  if (match == null) {
    throw FormatException('Invalid operating hours format: $value');
  }

  var hour = int.parse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  final period = match.group(3);

  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;

  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw FormatException('Invalid operating hours format: $value');
  }

  return TimeOfDay(hour: hour, minute: minute);
}

class ClinicsPage extends StatefulWidget {
  final VoidCallback? onUpdated;

  const ClinicsPage({super.key, this.onUpdated});

  @override
  State<ClinicsPage> createState() => _ClinicsPageState();
}

class _ClinicsPageState extends State<ClinicsPage> {
  final DashboardService _service = DashboardService();

  bool _isLoading = true;
  List<CenterModel> _clinics = [];
  String _searchText = '';

  static const Color primary = Color(0xFF0F719F);
  static const Color darkBlue = Color(0xFF0F3A55);
  static const Color mutedText = Color(0xFF647583);
  static const Color pageBg = Color(0xFFF4F8FB);

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);

    try {
      final clinics = await _service.fetchCenters();
      clinics.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;

      setState(() => _clinics = clinics);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load centers: $error')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<CenterModel> get _filteredClinics {
    if (_searchText.trim().isEmpty) return _clinics;

    final query = _searchText.toLowerCase().trim();

    return _clinics.where((clinic) {
      return clinic.name.toLowerCase().contains(query) ||
          clinic.address.toLowerCase().contains(query) ||
          clinic.city.toLowerCase().contains(query) ||
          clinic.contactNumber.toLowerCase().contains(query);
    }).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showClinicDialog([CenterModel? clinic]) async {
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController(text: clinic?.name ?? '');
    final addressController = TextEditingController(
      text: clinic?.address ?? '',
    );
    final cityController = TextEditingController(text: clinic?.city ?? '');
    final requirementsController = TextEditingController(
      text: clinic != null ? clinic.requirements : '',
    );
    final machinesController = TextEditingController(
      text: clinic?.machines.toString() ?? '0',
    );
    final slotsController = TextEditingController(
      text: clinic?.availableSlots.toString() ?? '0',
    );
    final hoursController = TextEditingController(
      text: clinic?.operatingHours ?? '',
    );
    final contactController = TextEditingController(
      text: clinic?.contactNumber ?? '',
    );

    bool isSaving = false;
    bool isFindingLocation = false;

    double? selectedLatitude = clinic?.latitude;
    double? selectedLongitude = clinic?.longitude;

    final mapController = MapController();

    Future<void> searchLocation(StateSetter setDialogState) async {
      final query = '${addressController.text} ${cityController.text}'.trim();

      if (query.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter an address or city first.'),
          ),
        );
        return;
      }

      setDialogState(() => isFindingLocation = true);

      try {
        final url =
            'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1';

        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Flutter App'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data.isNotEmpty) {
            final lat = double.parse(data[0]['lat']);
            final lon = double.parse(data[0]['lon']);

            setDialogState(() {
              selectedLatitude = lat;
              selectedLongitude = lon;
            });

            mapController.move(LatLng(lat, lon), 16);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No location found. Try a more specific address.',
                ),
              ),
            );
          }
        }
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to find location: $error')),
        );
      } finally {
        setDialogState(() => isFindingLocation = false);
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // CLEAN HEADER - NO DARK GRADIENT
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(26, 24, 22, 20),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE8F0F5)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF8FC),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    clinic == null
                                        ? Icons.add_business_rounded
                                        : Icons.edit_location_alt_rounded,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clinic == null
                                            ? 'Add New Center'
                                            : 'Edit Center Details',
                                        style: const TextStyle(
                                          color: darkBlue,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        clinic == null
                                            ? 'Create a new dialysis center profile.'
                                            : 'Update center information, capacity, and map location.',
                                        style: const TextStyle(
                                          color: mutedText,
                                          fontSize: 13.5,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: isSaving
                                      ? null
                                      : () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded),
                                  color: const Color(0xFF263B4A),
                                ),
                              ],
                            ),
                          ),

                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(26),
                              child: Form(
                                key: formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _SectionLabel(
                                      icon: Icons.info_outline_rounded,
                                      title: 'Basic Information',
                                    ),
                                    const SizedBox(height: 14),

                                    _buildTextField(
                                      controller: nameController,
                                      label: 'Center Name',
                                      icon: Icons.business_rounded,
                                    ),

                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _buildTextField(
                                            controller: addressController,
                                            label: 'Address',
                                            icon: Icons.location_on_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: cityController,
                                            label: 'City',
                                            icon: Icons.location_city_rounded,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 14),

                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.icon(
                                        onPressed: isFindingLocation
                                            ? null
                                            : () => searchLocation(
                                                setDialogState,
                                              ),
                                        icon: isFindingLocation
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.my_location_rounded,
                                              ),
                                        label: Text(
                                          isFindingLocation
                                              ? 'Finding...'
                                              : 'Find on Map',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    const _SectionLabel(
                                      icon: Icons.map_outlined,
                                      title: 'Center Location',
                                    ),

                                    const SizedBox(height: 12),

                                    Container(
                                      height: 285,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(0xFFD9E7EF),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: FlutterMap(
                                          mapController: mapController,
                                          options: MapOptions(
                                            initialCenter: LatLng(
                                              selectedLatitude ?? 14.5995,
                                              selectedLongitude ?? 120.9842,
                                            ),
                                            initialZoom: 13,
                                            onTap: (tapPosition, point) {
                                              setDialogState(() {
                                                selectedLatitude =
                                                    point.latitude;
                                                selectedLongitude =
                                                    point.longitude;
                                              });
                                            },
                                          ),
                                          children: [
                                            TileLayer(
                                              urlTemplate:
                                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                              userAgentPackageName:
                                                  'com.example.app',
                                            ),
                                            if (selectedLatitude != null &&
                                                selectedLongitude != null)
                                              MarkerLayer(
                                                markers: [
                                                  Marker(
                                                    point: LatLng(
                                                      selectedLatitude!,
                                                      selectedLongitude!,
                                                    ),
                                                    width: 44,
                                                    height: 44,
                                                    child: const Icon(
                                                      Icons.location_pin,
                                                      color: Color(0xFFEA5353),
                                                      size: 44,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        color: selectedLatitude != null
                                            ? const Color(0xFFEFF8FC)
                                            : const Color(0xFFFFF8E8),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selectedLatitude != null
                                                ? Icons.check_circle_rounded
                                                : Icons.touch_app_rounded,
                                            color: selectedLatitude != null
                                                ? primary
                                                : const Color(0xFFC7861B),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              selectedLatitude != null
                                                  ? 'Selected: Lat ${selectedLatitude!.toStringAsFixed(6)} | Lng ${selectedLongitude!.toStringAsFixed(6)}'
                                                  : 'Tap the map or use Find on Map to select the center location.',
                                              style: TextStyle(
                                                color: selectedLatitude != null
                                                    ? darkBlue
                                                    : const Color(0xFF8A651C),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    const _SectionLabel(
                                      icon: Icons.medical_services_outlined,
                                      title: 'Capacity and Operations',
                                    ),

                                    const SizedBox(height: 14),

                                    _buildTextField(
                                      controller: requirementsController,
                                      label: 'Requirements',
                                      icon: Icons.assignment_outlined,
                                      maxLines: 2,
                                    ),

                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            controller: machinesController,
                                            label: 'Machines',
                                            icon: Icons
                                                .precision_manufacturing_rounded,
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: slotsController,
                                            label: 'Available Slots',
                                            icon: Icons.event_available_rounded,
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            controller: hoursController,
                                            label: 'Operating Hours',
                                            icon: Icons.schedule_rounded,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: contactController,
                                            label: 'Contact Number',
                                            icon: Icons.phone_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF7FAFC),
                              border: Border(
                                top: BorderSide(color: Color(0xFFE5EEF4)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: isSaving
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }

                                          if (selectedLatitude == null ||
                                              selectedLongitude == null) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Please select a location on the map.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }

                                          setDialogState(() => isSaving = true);

                                          try {
                                            if (clinic == null) {
                                              await _service.createCenter(
                                                name: nameController.text
                                                    .trim(),
                                                address: addressController.text
                                                    .trim(),
                                                city: cityController.text
                                                    .trim(),
                                                requirements:
                                                    requirementsController.text
                                                        .trim(),
                                                latitude: selectedLatitude!,
                                                longitude: selectedLongitude!,
                                                slotAvailable:
                                                    int.tryParse(
                                                      slotsController.text
                                                          .trim(),
                                                    ) ??
                                                    0,
                                                machines:
                                                    int.tryParse(
                                                      machinesController.text
                                                          .trim(),
                                                    ) ??
                                                    0,
                                                shifts: 2,
                                                operatingHours: hoursController
                                                    .text
                                                    .trim(),
                                                contactNumber: contactController
                                                    .text
                                                    .trim(),
                                              );
                                            } else {
                                              await _service.updateCenter(
                                                centerId: clinic.id,
                                                name: nameController.text
                                                    .trim(),
                                                address: addressController.text
                                                    .trim(),
                                                city: cityController.text
                                                    .trim(),
                                                requirements:
                                                    requirementsController.text
                                                        .trim(),
                                                latitude: selectedLatitude!,
                                                longitude: selectedLongitude!,
                                                slotAvailable:
                                                    int.tryParse(
                                                      slotsController.text
                                                          .trim(),
                                                    ) ??
                                                    0,
                                                machines:
                                                    int.tryParse(
                                                      machinesController.text
                                                          .trim(),
                                                    ) ??
                                                    0,
                                                shifts: 2,
                                                operatingHours: hoursController
                                                    .text
                                                    .trim(),
                                                contactNumber: contactController
                                                    .text
                                                    .trim(),
                                              );
                                            }

                                            if (!mounted) return;

                                            Navigator.of(context).pop();

                                            await Future.delayed(
                                              const Duration(milliseconds: 180),
                                            );

                                            await _loadClinics();
                                            widget.onUpdated?.call();

                                            if (!mounted) return;

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  clinic == null
                                                      ? 'Center created successfully.'
                                                      : 'Center updated successfully.',
                                                ),
                                              ),
                                            );
                                          } catch (error) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Unable to save center: $error',
                                                ),
                                              ),
                                            );
                                          } finally {
                                            try {
                                              setDialogState(
                                                () => isSaving = false,
                                              );
                                            } catch (_) {}
                                          }
                                        },
                                  icon: isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: Text(
                                    isSaving ? 'Saving...' : 'Save Center',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
    cityController.dispose();
    requirementsController.dispose();
    machinesController.dispose();
    slotsController.dispose();
    hoursController.dispose();
    contactController.dispose();
  }

  Future<void> _deleteClinic(CenterModel clinic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEA5353)),
            SizedBox(width: 10),
            Text('Delete Center'),
          ],
        ),
        content: Text(
          'Deleting ${clinic.name} will deactivate all assigned admins.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA5353),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseConfig.client
          .from('profiles')
          .update({'status': 'inactive'})
          .eq('clinic_id', clinic.id)
          .eq('role', 'admin')
          .select();

      await SupabaseConfig.client
          .from('clinics')
          .update({'status': 'closed'})
          .eq('id', clinic.id);

      await ProfileService().logAction(
        action: 'delete_clinic',
        targetId: clinic.id,
        targetName: clinic.name,
      );

      if (!mounted) return;

      await _loadClinics();
      widget.onUpdated?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Center deleted. Admins set to inactive.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete center: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinics = _filteredClinics;
    final openCount = _clinics
        .where((clinic) => isCenterOpenByOperatingHours(clinic.operatingHours))
        .length;
    final totalSlots = _clinics.fold<int>(
      0,
      (sum, clinic) => sum + clinic.availableSlots,
    );
    final totalMachines = _clinics.fold<int>(
      0,
      (sum, clinic) => sum + clinic.machines,
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: pageBg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _HeaderCard(onAdd: () => _showClinicDialog()),
            ),

            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 850;

                final cards = [
                  _DashboardStatCard(
                    icon: Icons.business_rounded,
                    label: 'Total Centers',
                    value: _clinics.length.toString(),
                    description: 'Registered dialysis centers',
                  ),

                  _DashboardStatCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Open Centers',
                    value: openCount.toString(),
                    description: 'Currently marked as open',
                  ),

                  _DashboardStatCard(
                    icon: Icons.event_available_rounded,
                    label: 'Available Slots',
                    value: totalSlots.toString(),
                    description: 'Total remaining capacity',
                  ),

                  _DashboardStatCard(
                    icon: Icons.precision_manufacturing_rounded,
                    label: 'Machines',
                    value: totalMachines.toString(),
                    description: 'Total available machines',
                  ),
                ];

                if (isSmall) {
                  return Column(
                    children: cards.asMap().entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: cardWithDelay(entry.value, entry.key),
                      );
                    }).toList(),
                  );
                }

                return Row(
                  children: cards.asMap().entries.map((entry) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: entry.key == cards.length - 1 ? 0 : 12,
                        ),
                        child: cardWithDelay(entry.value, entry.key),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 22),

            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _SearchAndRefreshBar(
                searchText: _searchText,
                onSearchChanged: (value) {
                  setState(() => _searchText = value);
                },
                onRefresh: _loadClinics,
              ),
            ),

            const SizedBox(height: 22),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _isLoading
                  ? const _LoadingPanel()
                  : clinics.isEmpty
                  ? _EmptyPanel(
                      hasSearch: _searchText.trim().isNotEmpty,
                      onAdd: () => _showClinicDialog(),
                    )
                  : _CentersTableCard(
                      clinics: clinics,
                      formatDate: _formatDate,
                      onEdit: _showClinicDialog,
                      onDelete: _deleteClinic,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardWithDelay(Widget card, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (index * 80)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: card,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'This field is required';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCEAF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        filled: true,
        fillColor: const Color(0xFFF6FBFF),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final VoidCallback onAdd;

  const _HeaderCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F719F), Color(0xFF0F3A55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Centers Management',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage dialysis centers, operating details, capacity, and map locations in one organized workspace.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.84),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Center'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F719F),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String description;

  const _DashboardStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8F0F5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8FC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xFF0F719F)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F3A55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF263B4A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF647583),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndRefreshBar extends StatefulWidget {
  final String searchText;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;

  const _SearchAndRefreshBar({
    required this.searchText,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  @override
  State<_SearchAndRefreshBar> createState() => _SearchAndRefreshBarState();
}

class _SearchAndRefreshBarState extends State<_SearchAndRefreshBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchText);
  }

  @override
  void didUpdateWidget(covariant _SearchAndRefreshBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchText != widget.searchText &&
        _controller.text != widget.searchText) {
      _controller.text = widget.searchText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8F0F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _controller,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                hintText:
                    'Search by center name, city, address, or contact number...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          widget.onSearchChanged('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: const Color(0xFFF6FBFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEFF8FC),
              foregroundColor: const Color(0xFF0F719F),
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}

class _CentersTableCard extends StatelessWidget {
  final List<CenterModel> clinics;
  final String Function(DateTime date) formatDate;
  final void Function(CenterModel clinic) onEdit;
  final void Function(CenterModel clinic) onDelete;

  const _CentersTableCard({
    required this.clinics,
    required this.formatDate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('centers-table'),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE8F0F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF8FC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.view_list_rounded,
                  color: Color(0xFF0F719F),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centers List',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F3A55),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Review center details quickly and use actions to update or remove records.',
                      style: TextStyle(color: Color(0xFF647583)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF6FBFF),
                    ),
                    dataRowMinHeight: 68,
                    dataRowMaxHeight: 76,
                    columnSpacing: 34,
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade100),
                    ),
                    columns: const [
                      DataColumn(label: Text('Center')),
                      DataColumn(label: Text('City')),
                      DataColumn(label: Text('Slots')),
                      DataColumn(label: Text('Machines')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Created')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: clinics.map((clinic) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 300,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF8FC),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.local_hospital_rounded,
                                      color: Color(0xFF0F719F),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clinic.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF263B4A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          clinic.address,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF647583),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(Text(clinic.city)),
                          DataCell(
                            _MiniPill(
                              text: clinic.availableSlots.toString(),
                              icon: Icons.event_available_rounded,
                            ),
                          ),
                          DataCell(
                            _MiniPill(
                              text: clinic.machines.toString(),
                              icon: Icons.precision_manufacturing_rounded,
                            ),
                          ),
                          DataCell(
                            _StatusPill(
                              isOpen: isCenterOpenByOperatingHours(
                                clinic.operatingHours,
                              ),
                            ),
                          ),
                          DataCell(Text(formatDate(clinic.createdAt))),
                          DataCell(
                            Row(
                              children: [
                                _ActionIconButton(
                                  icon: Icons.edit_rounded,
                                  color: const Color(0xFF174E71),
                                  onTap: () => onEdit(clinic),
                                ),
                                const SizedBox(width: 8),
                                _ActionIconButton(
                                  icon: Icons.delete_rounded,
                                  color: const Color(0xFFEA5353),
                                  onTap: () => onDelete(clinic),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: color.withOpacity(0.14),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isOpen;

  const _StatusPill({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isOpen ? const Color(0xFFE9F8EF) : const Color(0xFFFFEEF0),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOpen ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 15,
            color: isOpen ? const Color(0xFF2E9E5B) : const Color(0xFFEA5353),
          ),
          const SizedBox(width: 6),
          Text(
            isOpen ? 'Open' : 'Closed',
            style: TextStyle(
              color: isOpen ? const Color(0xFF2E9E5B) : const Color(0xFFEA5353),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final IconData icon;

  const _MiniPill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF0F719F)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F3A55),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('loading'),
      width: double.infinity,
      padding: const EdgeInsets.all(50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading centers...',
            style: TextStyle(
              color: Color(0xFF647583),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onAdd;

  const _EmptyPanel({required this.hasSearch, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('empty'),
      width: double.infinity,
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE8F0F5)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8FC),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              hasSearch ? Icons.search_off_rounded : Icons.business_rounded,
              color: const Color(0xFF0F719F),
              size: 38,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasSearch
                ? 'No matching centers found'
                : 'No centers available yet',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F3A55),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try searching using another center name, city, address, or contact number.'
                : 'Create your first dialysis center to start managing capacity and operations.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF647583), height: 1.4),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Center'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F719F),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0F719F), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F3A55),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
