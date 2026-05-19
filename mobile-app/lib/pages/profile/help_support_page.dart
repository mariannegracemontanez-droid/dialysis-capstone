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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EBF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2F5),
              borderRadius: BorderRadius.circular(15),
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
                    color: Color(0xFF1F2933),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color.fromARGB(137, 0, 0, 0),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFAQItem({
    required IconData icon,
    required String question,
    required String answer,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EBF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: const Color(0xFFE8F2F5),
          highlightColor: const Color(0xFFE8F2F5),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF225E72), size: 21),
          ),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2933),
            ),
          ),
          iconColor: const Color(0xFF225E72),
          collapsedIconColor: Colors.grey,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFA),
                borderRadius: BorderRadius.circular(14),
              ),
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
      ),
    );
  }

  Widget buildSectionHeader({required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2933),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.4,
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
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
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
                          'Find answers, support details, and app resources.',
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
                    title: 'Call Your Clinic',
                    subtitle: clinicNumber,
                  ),
                  buildSupportTile(
                    icon: Icons.email_outlined,
                    title: 'Email Support',
                    subtitle: 'Soon to be updated',
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    title: 'Frequently Asked Questions',
                    subtitle:
                        'Quick answers to common questions about appointments, profile updates, records, and account privacy.',
                  ),
                  buildFAQItem(
                    icon: Icons.calendar_month_outlined,
                    question: 'How can I see my schedule?',
                    answer:
                        'You can view your dialysis schedule through the Schedule tab. This section provides an overview of your upcoming appointments and sessions. If you have any questions about your schedule, please contact your clinic for assistance.',
                  ),
                  buildFAQItem(
                    icon: Icons.person_outline,
                    question: 'How can I update my profile information?',
                    answer:
                        'Go to the Profile tab and select Edit Information. From there, you can review and update your personal details. Make sure to save your changes before leaving the page.',
                  ),
                  buildFAQItem(
                    icon: Icons.history_outlined,
                    question: 'How can I view my dialysis history?',
                    answer:
                        'Your dialysis records and schedule history can be found in the appointment and monitoring-related sections of the app. These sections help you review past sessions and upcoming care activities.',
                  ),
                  buildFAQItem(
                    icon: Icons.lock_outline,
                    question: 'Who can access my medical data?',
                    answer:
                        'Your medical information is only accessible to authorized healthcare providers and clinic administrators who need it for care coordination and clinic management.',
                  ),
                  buildFAQItem(
                    icon: Icons.notifications_none_outlined,
                    question: 'Why am I not receiving updates or reminders?',
                    answer:
                        'Check if your account information is updated and make sure your device notifications are enabled. You may also contact your clinic if an appointment update does not appear correctly.',
                  ),
                  buildFAQItem(
                    icon: Icons.help_outline,
                    question: 'What should I do if something looks incorrect?',
                    answer:
                        'If your schedule, clinic details, or profile information looks incorrect, contact your clinic or support staff so they can review and update the information if needed.',
                  ),
                  const SizedBox(height: 24),
                  buildSectionHeader(
                    title: 'Resources',
                    subtitle:
                        'Helpful references for learning how to use the app and understanding service guidelines.',
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2EBF0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.035),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F2F5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.menu_book_outlined,
                              color: Color(0xFF225E72),
                            ),
                          ),
                          title: const Text(
                            'User Guide',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Step-by-step guide for using CureNurture',
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F2F5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              color: Color(0xFF225E72),
                            ),
                          ),
                          title: const Text(
                            'Terms of Service',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Service guidelines and usage terms',
                          ),
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
