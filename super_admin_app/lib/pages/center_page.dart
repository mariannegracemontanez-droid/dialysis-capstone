import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/center_model.dart';
import '../services/dashboard_service.dart';
import '../config/supabase_config.dart';
import '../services/profile_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final clinics = await _service.fetchCenters();
      if (!mounted) return;
      setState(() {
        _clinics = clinics;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load centers: $error')),
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

Future<void> _showClinicDialog([CenterModel? clinic]) async {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController(text: clinic?.name ?? '');
  final addressController = TextEditingController(text: clinic?.address ?? '');
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
  double? selectedLatitude = clinic?.latitude;
  double? selectedLongitude = clinic?.longitude;

  final mapController = MapController();

  Future<void> searchLocation() async {
  final query =
      '${addressController.text} ${cityController.text}';

  if (query.trim().isEmpty) return;

  final url =
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1';

  final response = await http.get(
    Uri.parse(url),
    headers: {
      'User-Agent': 'Flutter App',
    },
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    if (data.isNotEmpty) {
      final lat = double.parse(data[0]['lat']);
      final lon = double.parse(data[0]['lon']);

     selectedLatitude = lat;
    selectedLongitude = lon;  

      mapController.move(
        LatLng(lat, lon),
        16,
      );
    }
  }
}

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(clinic == null ? 'Add Center' : 'Edit Center'),
            content: SizedBox(
              width: 400,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                  _buildTextField(controller: nameController, label: 'Center Name'),
                  _buildTextField(controller: addressController, label: 'Address'),
                  Row(
  children: [
    Expanded(
      child: _buildTextField(
        controller: cityController,
        label: 'City',
      ),
    ),

    const SizedBox(width: 10),

    ElevatedButton(
      onPressed: searchLocation,
      child: const Text('Find'),
    ),
  ],
),
                  const SizedBox(height: 16),

Container(
  height: 300,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade300),
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
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
            selectedLatitude = point.latitude;
            selectedLongitude = point.longitude;
          });
        },
      ),

      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
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
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ],
          ),
      ],
    ),
  ),
),

const SizedBox(height: 10),

Text(
  selectedLatitude != null
      ? 'Lat: ${selectedLatitude!.toStringAsFixed(6)} | Lng: ${selectedLongitude!.toStringAsFixed(6)}'
      : 'Tap on the map to select location',
),
                  _buildTextField(controller: requirementsController, label: 'Requirements'),

                  _buildTextField(
                    controller: machinesController,
                    label: 'Machines',
                    keyboardType: TextInputType.number,
                  ),

                _buildTextField(
                  controller: slotsController,
                  label: 'Available Slots',
                  keyboardType: TextInputType.number,
                ),

                _buildTextField(controller: hoursController, label: 'Operating Hours'),
                _buildTextField(controller: contactController, label: 'Contact Number'),
              ],
                  ),
                ),
              ),
            ),
            actions: [
              // CANCEL BUTTON
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),

              // SAVE BUTTON
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;

                        setDialogState(() {
                          isSaving = true;
                        });
                        if (selectedLatitude == null ||
                          selectedLongitude == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a location on the map'),
                          ),
                        );
                        return;
                      }

                        try {
                          if (clinic == null) {
                            await _service.createCenter(
                              name: nameController.text.trim(),
                              address: addressController.text.trim(),
                              city: cityController.text.trim(),
                              requirements: requirementsController.text.trim(),
                              latitude: selectedLatitude!,
                              longitude: selectedLongitude!,
                              slotAvailable:
                                  int.tryParse(slotsController.text.trim()) ?? 0,
                              machines:
                                  int.tryParse(machinesController.text.trim()) ?? 0,
                              shifts: 2,
                              operatingHours: hoursController.text.trim(),
                              contactNumber: contactController.text.trim(),
                              
                            );
                            await _loadClinics();      
                            widget.onUpdated?.call();  
                          } else {
                            await _service.updateCenter(
                              centerId: clinic.id,
                              name: nameController.text.trim(),
                              address: addressController.text.trim(),
                              city: cityController.text.trim(),
                              requirements: requirementsController.text.trim(),
                              latitude: selectedLatitude!,
                              longitude: selectedLongitude!,
                              slotAvailable:
                                  int.tryParse(slotsController.text.trim()) ?? 0,
                              machines:
                                  int.tryParse(machinesController.text.trim()) ?? 0,
                              shifts: 2,
                              operatingHours: hoursController.text.trim(),
                              contactNumber: contactController.text.trim(),
                            );
                            await _loadClinics();      
                            widget.onUpdated?.call();  
                          }

                          // ✅ REFRESH UI + DASHBOARD
                            await _loadClinics();         // refresh table
                            widget.onUpdated?.call();     

                          if (!mounted) return;
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                clinic == null
                                    ? 'Center created successfully.'
                                    : 'Center updated successfully.',
                              ),
                            ),
                          );
                        } catch (error) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Unable to save center: $error'),
                            ),
                          );
                        } finally {
                          setDialogState(() {
                            isSaving = false;
                          });
                        }
                      },
                child: Text(isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

 Future<void> _deleteClinic(CenterModel clinic) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Center'),
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
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    print("Deleting clinic ID: ${clinic.id}");

    // 🔥 STEP 1: DEACTIVATE ADMINS (ONLY ONCE)
    final updatedAdmins = await SupabaseConfig.client
        .from('profiles')
        .update({'status': 'inactive'})
        .eq('clinic_id', clinic.id)
        .eq('role', 'admin')
        .select();

    print("Admins deactivated: $updatedAdmins");

    // 🔥 STEP 2: DELETE CLINIC
    await SupabaseConfig.client
        .from('clinics')
        .delete()
        .eq('id', clinic.id);

    // 🔥 STEP 3: AUDIT LOG (AFTER SUCCESS)
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
      SnackBar(
        content: Text('Unable to delete center: $error'),
      ),
    );
  }
}
  List<CenterModel> get _filteredClinics {
    if (_searchText.isEmpty) return _clinics;
    return _clinics.where((clinic) {
      final query = _searchText.toLowerCase();
      return clinic.name.toLowerCase().contains(query) ||
          clinic.address.toLowerCase().contains(query) ||
          clinic.contactNumber.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clinics = _filteredClinics;
    final openCount = _clinics.where((clinic) => clinic.isOpen).length;
    final totalSlots = _clinics.fold<int>(0, (sum, clinic) => sum + clinic.availableSlots);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Centers Management', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF0F3A55))),
                      SizedBox(height: 8),
                      Text('Manage dialysis centers, capacity, and operational status across the network.', style: TextStyle(fontSize: 16, color: Color(0xFF647583))),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showClinicDialog(),
                  
                  icon: const Icon(Icons.add),
                  label: const Text('New Center'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F719F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _InfoChip(label: 'Active centers', value: _clinics.length.toString()),
                const SizedBox(width: 12),
                _InfoChip(label: 'Open now', value: openCount.toString()),
                const SizedBox(width: 12),
                _InfoChip(label: 'Total available slots', value: totalSlots.toString()),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              onChanged: (value) => setState(() => _searchText = value),
              decoration: InputDecoration(
                hintText: 'Search centers by name, location, contact...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : clinics.isEmpty
                    ? const Center(child: Text('No centers available. Create a new dialysis center to begin.'))
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 8))],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Center Name')),
                              DataColumn(label: Text('Date Created')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: clinics.map((clinic) {
                              return DataRow(cells: [
                                DataCell(Text(clinic.name)),
                                DataCell(Text('${clinic.createdAt.year}-${clinic.createdAt.month.toString().padLeft(2, '0')}-${clinic.createdAt.day.toString().padLeft(2, '0')}')),
                                DataCell(Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _showClinicDialog(clinic),
                                      icon: const Icon(Icons.edit, color: Color(0xFF174E71)),
                                      tooltip: 'Edit',
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteClinic(clinic),
                                      icon: const Icon(Icons.delete, color: Color(0xFFEA5353)),
                                      tooltip: 'Delete',
                                    ),
                                  ],
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
          ],
        ),
      ),
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
        fillColor: const Color(0xFFF6FBFF),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Color(0xFF647583))),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;

  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF5E7385))),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}
