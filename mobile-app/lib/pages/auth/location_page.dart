import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/signup_data.dart';

class LocationPage extends StatefulWidget {
  final SignupData signupData;

  const LocationPage({super.key, required this.signupData});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _barangayController = TextEditingController();
  final MapController _mapController = MapController();

  final List<String> _ncrCities = [
    'Caloocan',
    'Las Piñas',
    'Makati',
    'Malabon',
    'Mandaluyong',
    'Manila',
    'Marikina',
    'Muntinlupa',
    'Navotas',
    'Parañaque',
    'Pasay',
    'Pasig',
    'Quezon City',
    'San Juan',
    'Taguig',
    'Valenzuela',
    'Pateros',
  ];

  final Map<String, List<String>> _barangayData = {
    'Caloocan': ['Bagumbayan', 'Baesa', 'North Bay Boulevard South'],
    'Las Piñas': ['Talaba', 'Pamplona', 'Daniel Fajardo'],
    'Makati': ['Poblacion', 'San Antonio', 'Bel-Air'],
    'Malabon': ['Tañong', 'Potrero', 'Longos'],
    'Mandaluyong': ['Wack-Wack Greenhills', 'Hulo', 'Plainview'],
    'Manila': ['Tondo', 'Binondo', 'Malate', 'Ermita', 'Intramuros'],
    'Marikina': ['Concepcion', 'San Roque', 'Parang'],
    'Muntinlupa': ['Alabang', 'Tunasan', 'Putatan'],
    'Navotas': ['Tanza', 'Bagumbayan North', 'San Jose'],
    'Parañaque': ['BF Homes', 'San Dionisio', 'Tambo'],
    'Pasay': ['Malibay', 'Maricaban', 'Merville'],
    'Pasig': ['Bagong Ilog', 'Kapitolyo', 'San Miguel'],
    'Quezon City': ['Diliman', 'Novaliches', 'Project 6', 'Katipunan'],
    'San Juan': ['Greenhills', 'Addition Hills', 'Hibla'],
    'Taguig': ['Bonifacio Global City', 'McKinley Hill', 'Silangan'],
    'Valenzuela': ['Marulas', 'Dalandanan', 'Maysan', 'Malinta', 'Rincon', 'Malanday'],
    'Pateros': ['Poblacion', 'A. Mabini', 'San Roque'],
  };

  final Map<String, LatLng> _cityCoordinates = {
    'Caloocan': LatLng(14.7563, 121.0437),
    'Las Piñas': LatLng(14.4542, 121.0223),
    'Makati': LatLng(14.5547, 121.0244),
    'Malabon': LatLng(14.6544, 120.9564),
    'Mandaluyong': LatLng(14.5827, 121.0360),
    'Manila': LatLng(14.5995, 120.9842),
    'Marikina': LatLng(14.6504, 121.1023),
    'Muntinlupa': LatLng(14.4114, 121.0437),
    'Navotas': LatLng(14.6598, 120.9410),
    'Parañaque': LatLng(14.4800, 121.0223),
    'Pasay': LatLng(14.5378, 121.0014),
    'Pasig': LatLng(14.5764, 121.0851),
    'Quezon City': LatLng(14.6760, 121.0437),
    'San Juan': LatLng(14.5833, 121.0369),
    'Taguig': LatLng(14.5176, 121.0509),
    'Valenzuela': LatLng(14.7094, 120.9830),
    'Pateros': LatLng(14.5600, 121.0500),
  };

  final Map<String, List<Map<String, dynamic>>> _dialysisCenters = {
    'Manila': [
      {'name': 'Manila Kidney Care', 'position': LatLng(14.5934, 120.9842)},
      {'name': 'Intramuros Dialysis', 'position': LatLng(14.5919, 120.9775)},
    ],
    'Quezon City': [
      {
        'name': 'Quezon CIty Renal Center',
        'position': LatLng(14.6488, 121.0509),
      },
      {
        'name': 'Diliman Dialysis Clinic',
        'position': LatLng(14.6580, 121.0244),
      },
    ],
    'Makati': [
      {
        'name': 'Makati Dialysis Hospital',
        'position': LatLng(14.5643, 121.0241),
      },
      {'name': 'Poblacion Renal Care', 'position': LatLng(14.5548, 121.0240)},
    ],
    'Taguig': [
      {
        'name': 'Bonifacio Dialysis Center',
        'position': LatLng(14.5547, 121.0493),
      },
      {'name': 'McKinley Renal Care', 'position': LatLng(14.5565, 121.0464)},
    ],
  };

  List<String> _availableBarangays = [];
  List<Marker> _dialysisMarkers = [];
  LatLng _mapCenter = LatLng(14.657, 121.0198);

  @override
  void initState() {
    super.initState();
    _provinceController.text = 'NCR';
    _cityController.text = widget.signupData.city;
    _barangayController.text = widget.signupData.barangay;
    _updateBarangayOptions();
    _updateMapMarkers();
  }

  @override
  void dispose() {
    _provinceController.dispose();
    _cityController.dispose();
    _barangayController.dispose();
    super.dispose();
  }

  void _updateBarangayOptions() {
    _availableBarangays = _barangayData[_cityController.text] ?? [];
    if (!_availableBarangays.contains(_barangayController.text)) {
      _barangayController.clear();
    }
  }

  void _updateMapMarkers() {
    final city = _cityController.text;
    if (city.isEmpty) {
      setState(() {
        _dialysisMarkers = [];
        _mapCenter = LatLng(14.657, 121.0198);
      });
      return;
    }

    final center = _cityCoordinates[city];
    final centers = _dialysisCenters[city] ?? [];
    setState(() {
      if (center != null) {
        _mapCenter = center;
        _mapController.move(_mapCenter, 12);
      }
      _dialysisMarkers = centers
          .map(
            (data) => Marker(
              width: 40,
              height: 40,
              point: data['position'] as LatLng,
              builder: (context) => const Icon(
                Icons.location_on,
                color: Color(0xFFE63946),
                size: 32,
              ),
            ),
          )
          .toList();
    });
  }

  void _handleNext() {
    final updated = widget.signupData.copyWith(
      province: _provinceController.text.trim(),
      city: _cityController.text.trim(),
      barangay: _barangayController.text.trim(),
      locationSummary:
          '${_provinceController.text.trim()}, ${_cityController.text.trim()}, ${_barangayController.text.trim()}',
    );

    Navigator.of(context).pushNamed('/medical-documents', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF2C5F7D),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Where are you located?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Your location helps us show clinics and centers closest to you.',
                      style: TextStyle(color: Color(0xFFD5E4EE), fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: 0.66,
                      color: const Color(0xFF2C5F7D),
                      backgroundColor: const Color(0xFFDDE6EA),
                      minHeight: 9,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            child: SizedBox(
                              height: 220,
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  center: _mapCenter,
                                  zoom: 11,
                                  minZoom: 3,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    subdomains: const ['a', 'b', 'c'],
                                    userAgentPackageName:
                                        'com.example.dialysis_patient_app',
                                  ),
                                  if (_dialysisMarkers.isNotEmpty)
                                    MarkerLayer(markers: _dialysisMarkers),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _provinceController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: 'Province',
                                    filled: true,
                                    fillColor: const Color(0xFFF7FBFF),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _cityController.text.isEmpty
                                      ? null
                                      : _cityController.text,
                                  items: _ncrCities
                                      .map(
                                        (city) => DropdownMenuItem(
                                          value: city,
                                          child: Text(city),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _cityController.text = value;
                                      _barangayController.clear();
                                      _updateBarangayOptions();
                                      _updateMapMarkers();
                                    });
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'City',
                                    filled: true,
                                    fillColor: const Color(0xFFF7FBFF),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _barangayController.text.isEmpty
                                      ? null
                                      : _barangayController.text,
                                  items: _availableBarangays
                                      .map(
                                        (barangay) => DropdownMenuItem(
                                          value: barangay,
                                          child: Text(barangay),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _barangayController.text = value;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Barangay',
                                    filled: true,
                                    fillColor: const Color(0xFFF7FBFF),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _handleNext,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2C5F7D),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('Next'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
