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

  @override
  void initState() {
    super.initState();
    _provinceController.text = widget.signupData.province;
    _cityController.text = widget.signupData.city;
    _barangayController.text = widget.signupData.barangay;
  }

  @override
  void dispose() {
    _provinceController.dispose();
    _cityController.dispose();
    _barangayController.dispose();
    super.dispose();
  }

  void _handleNext() {
    final updated = widget.signupData.copyWith(
      province: _provinceController.text.trim(),
      city: _cityController.text.trim(),
      barangay: _barangayController.text.trim(),
      locationSummary:
          '${_provinceController.text.trim()}, ${_cityController.text.trim()}, ${_barangayController.text.trim()}',
    );

    Navigator.of(context).pushNamed('/confirm-info', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F9FB),
        iconTheme: const IconThemeData(color: Color(0xFF2C5F7D)),
        title: const Text(
          'Where are you located?',
          style: TextStyle(color: Color(0xFF2C5F7D)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: 0.66,
                  color: const Color(0xFF2C5F7D),
                  backgroundColor: const Color(0xFFDDE6EA),
                  minHeight: 8,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your location helps us show clinics and centers closest to you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Color(0xFF3B5D6C)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: FlutterMap(
                  options: MapOptions(
                    center: LatLng(14.657, 121.0198),
                    zoom: 11,
                    minZoom: 3,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.example.dialysis_patient_app',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                TextField(
                  controller: _provinceController,
                  decoration: InputDecoration(
                    hintText: 'Province',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cityController,
                  decoration: InputDecoration(
                    hintText: 'City',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _barangayController,
                  decoration: InputDecoration(
                    hintText: 'Barangay',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
    );
  }
}
