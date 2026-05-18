import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_guide_page.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String clinicNumber = 'Loading...';

  @override
  void initState() {
    super.initState();
    fetchClinicContact();
  }

  Future<void> fetchClinicContact() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) return;

      final patient = await _supabase
          .from('patients')
          .select('clinic_id')
          .eq('id', user.id)
          .maybeSingle();

      if (patient == null) return;

      final clinic = await _supabase
          .from('clinics')
          .select('contact_number')
          .eq('id', patient['clinic_id'])
          .maybeSingle();

      if (clinic != null && mounted) {
        setState(() {
          clinicNumber = clinic['contact_number'] ?? 'No contact available';
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Widget buildSupportTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EBF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF225E72)),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFAQItem({required String question, required String answer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EBF0)),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),

      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF225E72),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),

              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),

                  const SizedBox(width: 10),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Help & Support',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        SizedBox(height: 4),

                        Text(
                          'Need assistance? We are here to help.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  buildSupportTile(
                    icon: Icons.call_outlined,
                    title: 'Call Us',
                    subtitle: clinicNumber,
                  ),

                  buildSupportTile(
                    icon: Icons.email_outlined,
                    title: 'Email Support',
                    subtitle: 'Soon to be updated',
                  ),

                  buildSupportTile(
                    icon: Icons.access_time_outlined,
                    title: 'Support Hours',
                    subtitle: 'Monday - Friday\n8:00 AM - 5:00 PM',
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Frequently Asked Questions',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  buildFAQItem(
                    question: 'How can I schedule an appointment?',
                    answer:
                        'You can schedule your dialysis appointment through the Schedule tab inside the application.',
                  ),

                  buildFAQItem(
                    question: 'How can I update my profile information?',
                    answer:
                        'You can update your profile information inside the Profile tab by clicking Edit Information.',
                  ),

                  buildFAQItem(
                    question: 'How can I view my dialysis history?',
                    answer:
                        'Your dialysis schedules and records are available in your appointment and monitoring sections.',
                  ),

                  buildFAQItem(
                    question: 'Who can access my medical data?',
                    answer:
                        'Only authorized healthcare providers and clinic administrators can securely access your medical records.',
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Resources',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2EBF0)),
                    ),

                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.menu_book_outlined,
                            color: Color(0xFF225E72),
                          ),

                          title: const Text(
                            'User Guide',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),

                          subtitle: const Text('Complete app documentation'),

                          trailing: const Icon(Icons.chevron_right),

                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const UserGuidePage(),
                              ),
                            );
                          },
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading: const Icon(
                            Icons.description_outlined,
                            color: Color(0xFF225E72),
                          ),

                          title: const Text(
                            'Terms of Service',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),

                          subtitle: const Text('Read our terms and conditions'),

                          trailing: const Icon(Icons.chevron_right),

                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Terms of Service soon to be available.',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
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
