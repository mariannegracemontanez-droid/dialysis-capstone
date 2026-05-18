import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
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

  LatLng? _userLocation;
  bool _isGettingLocation = false;
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _clinics = [];
  Map<String, dynamic>? _selectedClinic;
  Set<String> _appliedClinicIds = {};

  @override
  void initState() {
    super.initState();
    _loadClinicsAndApplications();
    _getUserLocation();
  }

  Future<void> _loadClinicsAndApplications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;

      final data = await Supabase.instance.client.from('clinics').select();

      final clinics = (data as List).cast<Map<String, dynamic>>().where((
        clinic,
      ) {
        final city = clinic['city']?.toString().toLowerCase() ?? '';
        final region = clinic['region']?.toString().toLowerCase() ?? '';
        return city.contains('valenzuela') || region.contains('ncr');
      }).toList();

      Set<String> appliedClinicIds = {};

      if (user != null) {
        final applications = await Supabase.instance.client
            .from('patients')
            .select('clinic_id')
            .eq('profile_id', user.id)
            .inFilter('status', ['pending', 'approved', 'active', 'no_sched']);

        appliedClinicIds = (applications as List)
            .map((row) => row['clinic_id']?.toString())
            .whereType<String>()
            .toSet();
      }

      setState(() {
        _clinics = clinics;
        _appliedClinicIds = appliedClinicIds;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Unable to load clinics. Please try again later.';
        _isLoading = false;
      });
    }
  }

  Future<void> _getUserLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Please turn on your phone location/GPS.';
          _isGettingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _errorMessage =
              'Location permission is required to show your location.';
          _isGettingLocation = false;
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage =
              'Location permission is permanently denied. Please enable it in app settings.';
          _isGettingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final currentLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _userLocation = currentLocation;
        _isGettingLocation = false;
      });

      _mapController.move(currentLocation, 15);
    } catch (e) {
      setState(() {
        _errorMessage = 'Unable to get your current location.';
        _isGettingLocation = false;
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

      final isAlreadyApplied = _appliedClinicIds.contains(
        clinic['id'].toString(),
      );

      markers.add(
        Marker(
          width: 48,
          height: 48,
          point: point,
          child: GestureDetector(
            onTap: isAlreadyApplied
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You already have an application for this clinic.',
                        ),
                      ),
                    );
                  }
                : () => _showClinicPopup(clinic),
            child: Icon(
              Icons.local_hospital,
              color: isAlreadyApplied
                  ? Colors.grey
                  : _selectedClinic != null &&
                        _selectedClinic!['id'] == clinic['id']
                  ? Colors.green
                  : Colors.red,
              size: 32,
            ),
          ),
        ),
      );
    }
    if (_userLocation != null) {
      markers.add(
        Marker(
          width: 52,
          height: 52,
          point: _userLocation!,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 36),
        ),
      );
    }
    return markers;
  }

  String _getDistanceFromUser(Map<String, dynamic> clinic) {
    if (_userLocation == null) return 'Distance unavailable';

    final latitude = double.tryParse(clinic['latitude'].toString());
    final longitude = double.tryParse(clinic['longitude'].toString());

    if (latitude == null || longitude == null) {
      return 'Distance unavailable';
    }

    final distanceInMeters = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      latitude,
      longitude,
    );

    final distanceInKm = distanceInMeters / 1000;

    return '${distanceInKm.toStringAsFixed(2)} km away';
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
                              _getDistanceFromUser(clinic),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C5F7D),
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
    if (_appliedClinicIds.contains(_selectedClinic!['id'].toString())) {
      setState(() {
        _errorMessage = 'You already have an application for this clinic.';
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                    borderRadius: BorderRadius.circular(14),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: Color(0xFF2C5F7D),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Choose Location',
                    style: TextStyle(
                      color: Color(0xFF173B4F),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                'Select your preferred dialysis center and review the clinic requirements before continuing.',
                style: TextStyle(
                  color: Color(0xFF6B7C86),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  const Text(
                    'Step 2 of 5',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '40%',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  value: 0.4,
                  minHeight: 8,
                  color: Color(0xFF2C5F7D),
                  backgroundColor: Color(0xFFDDEAF0),
                ),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1EAF0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          child: Stack(
                            children: [
                              FlutterMap(
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
                                    MarkerLayer(
                                      markers: _buildMarkers(_clinics),
                                    ),
                                ],
                              ),

                              Positioned(
                                top: 14,
                                left: 14,
                                right: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        color: Color(0xFF2C5F7D),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedClinic == null
                                              ? 'Tap a clinic marker to view details'
                                              : 'Clinic selected',
                                          style: const TextStyle(
                                            color: Color(0xFF173B4F),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
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

                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_isLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 30),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF2C5F7D),
                                      ),
                                    ),
                                  )
                                else if (_errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.20),
                                      ),
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                else ...[
                                  if (_selectedClinic == null)
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color.fromARGB(
                                          255,
                                          88,
                                          164,
                                          202,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFE3EDF2),
                                        ),
                                      ),
                                      child: const Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            color: Color(0xFF2C5F7D),
                                            size: 20,
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Please choose a clinic from the map to continue.',
                                              style: TextStyle(
                                                color: Color(0xFF5B6D7D),
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    _buildClinicDetailsCard(_selectedClinic!),

                                  const SizedBox(height: 18),

                                  SizedBox(
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _handleNext,
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        backgroundColor: const Color(
                                          0xFF2C5F7D,
                                        ),
                                        disabledBackgroundColor: const Color(
                                          0xFF2C5F7D,
                                        ).withOpacity(0.50),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'NEXT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
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
