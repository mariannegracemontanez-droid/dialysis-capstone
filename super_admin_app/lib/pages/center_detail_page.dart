import 'package:flutter/material.dart';
import '../models/center_model.dart';
import '../services/dashboard_service.dart'; // make sure this import path is correct

class CenterDetailPage extends StatelessWidget {
  final CenterModel center;

  const CenterDetailPage({super.key, required this.center});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(center.name),
        backgroundColor: const Color(0xFF174E71),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x11000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(center.name,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(center.address ?? '--',
                                style: const TextStyle(
                                    color: Color(0xFF4E6B7E), fontSize: 14)),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(center.status ?? 'Unknown'),
                        backgroundColor: center.status == 'Open'
                            ? const Color(0xFFE3F9F5)
                            : const Color(0xFFFFECEB),
                        labelStyle: TextStyle(
                          color: center.status == 'Open'
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF9D0208),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Operating Hours: ${center.operatingHours ?? '--'}"),
                  Text("Contact: ${center.contactNumber ?? '--'}"),
                  Text("Slots Available: ${center.availableSlots ?? '--'}"),
                  Text("Machines: ${center.machines ?? '--'}"),
                  Text("Total Patients: ${center.totalPatients ?? '--'}"),
                  Text("Shifts: ${center.shifts ?? '--'}"),
                  Text(
                  "Requirements: ${center.requirements.join(', ')}",
                ),

                  const SizedBox(height: 24),

                  // 👉 Update Button
                  ElevatedButton(
                    onPressed: () async {
                      await DashboardService().updateCenter(
                      centerId: center.id,
                      name: center.name,
                      address: center.address ?? '',
                      city: center.city ?? '',
                      requirements: List<String>.from(center.requirements ?? []), // ✅ SAFE
                      latitude: center.latitude ?? 0.0,
                      longitude: center.longitude ?? 0.0,
                      slotAvailable: center.availableSlots,
                      machines: center.machines,
                      shifts: center.shifts,
                      operatingHours: center.operatingHours ?? '',
                      contactNumber: center.contactNumber ?? '',
                    );
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Center updated successfully!'),
                        ),
                      );

                      Navigator.pop(context, true); // go back and refresh dashboard
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF174E71),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Update Center',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
