import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/signup_data.dart';
import 'clinic_info_page.dart';

class LocationPage extends StatefulWidget {
  final SignupData signupData;

  const LocationPage({super.key, required this.signupData});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final MapController _mapController = MapController();
  final LatLng _valenzuelaCenter = LatLng(14.7094, 120.9830);

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _clinics = [];
  Map<String, dynamic>? _selectedClinic;

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await Supabase.instance.client.from('clinics').select();

      final clinics = (data as List).cast<Map<String, dynamic>>().where((
        clinic,
      ) {
        final city = clinic['city']?.toString().toLowerCase() ?? '';
        final region = clinic['region']?.toString().toLowerCase() ?? '';
        return city.contains('valenzuela') || region.contains('ncr');
      }).toList();
      for (final clinic in clinics) {
        print('Clinic data: $clinic');
      }

      setState(() {
        _clinics = clinics;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Unable to load clinics. Please try again later.';
        _isLoading = false;
      });
    }
  }

  List<Marker> _buildMarkers(List<Map<String, dynamic>> clinics) {
    final markers = <Marker>[];
    for (final clinic in clinics) {
      final latitude = clinic['latitude'];
      final longitude = clinic['longitude'];
      if (latitude == null || longitude == null) continue;

      final point = LatLng(
        latitude is double
            ? latitude
            : double.tryParse(latitude.toString()) ?? 0,
        longitude is double
            ? longitude
            : double.tryParse(longitude.toString()) ?? 0,
      );

      markers.add(
        Marker(
          width: 48,
          height: 48,
          point: point,
          child: GestureDetector(
            onTap: () => _showClinicPopup(clinic),
            child: Icon(
              Icons.local_hospital,
              color:
                  _selectedClinic != null &&
                      _selectedClinic!['id'] == clinic['id']
                  ? Colors.green
                  : Colors.red,
              size: 32,
            ),
          ),
        ),
      );
    }
    return markers;
  }

  void _showClinicPopup(Map<String, dynamic> clinic) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C5F7D),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.local_hospital,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clinic['name']?.toString() ?? 'Clinic',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (clinic['address'] != null)
                            Text(
                              clinic['address'].toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF5B6D7D),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (clinic['operating_hours'] != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Operating Hours',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7A8696),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              clinic['operating_hours'].toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (clinic['contact_number'] != null) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Contact',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7A8696),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              clinic['contact_number'].toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                if (clinic['requirements'] != null) ...[
                  const Text(
                    'Required documents',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._buildRequirementItems(clinic['requirements']),
                  const SizedBox(height: 16),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedClinic = clinic;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Choose this clinic'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeClinicRequirement(dynamic requirement) {
    final raw = requirement?.toString() ?? '';
    return raw
        .replaceAll(RegExp(r'\s*/\s*'), ' / ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _extractClinicRequirements(dynamic requirements) {
    final items = requirements is List
        ? requirements.cast<dynamic>().map((item) => item.toString()).toList()
        : [requirements?.toString() ?? ''];

    return items
        .map(_normalizeClinicRequirement)
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _handleNext() {
    if (_selectedClinic == null) {
      setState(() {
        _errorMessage = 'Please choose a clinic before continuing.';
      });
      return;
    }
    final updated = widget.signupData.copyWith(
      clinicId: _selectedClinic!['id'],
      clinicName: _selectedClinic!['name']?.toString() ?? '',
      clinicRequirements: _extractClinicRequirements(
        _selectedClinic!['requirements'],
      ),
    );

    Navigator.of(context).pushNamed(
      '/clinic-info',
      arguments: ClinicInfoArguments(
        signupData: updated,
        clinic: _selectedClinic!,
      ),
    );
  }

  List<Widget> _buildRequirementItems(dynamic requirements) {
    final items = requirements is List
        ? requirements.cast<dynamic>().map((e) => e.toString()).toList()
        : [requirements.toString()];

    return items.map((requirement) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF2C5F7D),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(requirement, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildClinicDetailsCard(Map<String, dynamic> clinic) {
    final requirements = clinic['requirements'];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C5F7D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.local_hospital,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clinic['name']?.toString() ?? 'Clinic selected',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (clinic['address'] != null)
                        Text(
                          clinic['address'].toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF5B6D7D),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (clinic['operating_hours'] != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Operating Hours',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A8696),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          clinic['operating_hours'].toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (clinic['contact_number'] != null) ...[
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A8696),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          clinic['contact_number'].toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (requirements != null) ...[
              const SizedBox(height: 18),
              const Text(
                'Required documents',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._buildRequirementItems(requirements),
            ],
          ],
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF2C5F7D),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Choose Location',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Select your preferred dialysis center in Valenzuela and review the requirements before continuing.',
                style: TextStyle(color: Color(0xFF5B6D7D), fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _valenzuelaCenter,
                              initialZoom: 13,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                subdomains: const ['a', 'b', 'c'],
                                userAgentPackageName:
                                    'com.example.dialysis_patient_app',
                              ),
                              if (_clinics.isNotEmpty)
                                MarkerLayer(markers: _buildMarkers(_clinics)),
                            ],
                          ),
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_isLoading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                else if (_errorMessage != null)
                                  Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.red),
                                  )
                                else ...[
                                  if (_selectedClinic != null) ...[
                                    _buildClinicDetailsCard(_selectedClinic!),
                                    const SizedBox(height: 16),
                                  ],
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _handleNext,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2C5F7D,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Next',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
