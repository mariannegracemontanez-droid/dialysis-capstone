import 'package:flutter/material.dart';

class ClinicDetailPage extends StatelessWidget {
  final Map<String, dynamic> clinic;
  final bool isAlreadyApplied;

  const ClinicDetailPage({
    super.key,
    required this.clinic,
    this.isAlreadyApplied = false,
  });

  List<String> _requirementItems(dynamic requirements) {
    final items = requirements is List
        ? requirements.cast<dynamic>().map((e) => e.toString()).toList()
        : [requirements?.toString() ?? ''];

    return items
        .map(
          (item) => item
              .replaceAll(RegExp(r'\s*/\s*'), ' / ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        )
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final requirements = _requirementItems(clinic['requirements']);

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
                  const Expanded(
                    child: Text(
                      'Clinic Details',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 54,
                              width: 54,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C5F7D),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.local_hospital_rounded,
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
                                      color: Color(0xFF173B4F),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (clinic['address'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      clinic['address'].toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF6B7C86),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            if (clinic['operating_hours'] != null)
                              Expanded(
                                child: _buildInfoItem(
                                  'Operating Hours',
                                  clinic['operating_hours'].toString(),
                                  Icons.schedule_outlined,
                                ),
                              ),
                            if (clinic['contact_number'] != null) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                child: _buildInfoItem(
                                  'Contact',
                                  clinic['contact_number'].toString(),
                                  Icons.phone_outlined,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (requirements.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 18,
                                color: Color(0xFF2C5F7D),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Required Documents',
                                style: TextStyle(
                                  color: Color(0xFF173B4F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ...requirements.map(
                            (requirement) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
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
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      requirement,
                                      style: const TextStyle(
                                        color: Color(0xFF5B6D7D),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (isAlreadyApplied) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.30),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'You already have an application for this clinic.',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: isAlreadyApplied
                      ? null
                      : () => Navigator.of(context).pop(clinic),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2C5F7D),
                    disabledBackgroundColor: const Color(
                      0xFF2C5F7D,
                    ).withOpacity(0.50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isAlreadyApplied
                        ? 'Already Applied'
                        : 'Select This Clinic',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EDF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2C5F7D)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF7A8A94), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF173B4F),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
