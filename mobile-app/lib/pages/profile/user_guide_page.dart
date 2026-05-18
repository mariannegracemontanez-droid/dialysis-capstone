import 'package:flutter/material.dart';

class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  Widget _guideSection({
    required String title,
    required String subtitle,
    required List<Map<String, String>> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ...items.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2EBF0)),
            ),
            child: ExpansionTile(
              leading: const Icon(
                Icons.chevron_right,
                color: Color(0xFF1F8A9B),
              ),
              title: Text(
                item['title']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item['content']!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
      ],
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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User Guide',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Complete app documentation',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2EBF0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search, color: Colors.black54),
                        SizedBox(width: 10),
                        Text(
                          'Search for guide...',
                          style: TextStyle(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Quick Access',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: const [
                      _QuickAccessCard(
                        icon: Icons.book_outlined,
                        title: 'Getting Started',
                        subtitle: 'Learn the basics',
                      ),
                      _QuickAccessCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'Appointments',
                        subtitle: 'Manage sessions',
                      ),
                      _QuickAccessCard(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'Donation Drives',
                        subtitle: 'Donation events',
                      ),
                      _QuickAccessCard(
                        icon: Icons.medical_information_outlined,
                        title: 'Medical Records',
                        subtitle: 'Health history',
                      ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  _guideSection(
                    title: 'Getting Started',
                    subtitle: 'Learn the basics of CureNurture',
                    items: [
                      {
                        'title': 'Creating your Account',
                        'content':
                            'Create your account by filling out the registration form, submitting your information, and waiting for clinic approval.',
                      },
                      {
                        'title': 'Setting Up your Profile',
                        'content':
                            'Go to the Profile tab to update your contact details, medical information, and profile photo.',
                      },
                      {
                        'title': 'Navigating the App',
                        'content':
                            'Use the bottom navigation bar to access Home, Schedule, Donations, and Profile sections.',
                      },
                      {
                        'title': 'Customizing Notification',
                        'content':
                            'You can view system reminders and updates from the Notifications page.',
                      },
                    ],
                  ),

                  _guideSection(
                    title: 'Appointments',
                    subtitle: 'Managing your dialysis sessions',
                    items: [
                      {
                        'title': 'Booking a New Appointment',
                        'content':
                            'Go to the Schedule tab, select your preferred date and available time slot, then confirm your booking.',
                      },
                      {
                        'title': 'Viewing Upcoming Sessions',
                        'content':
                            'Your upcoming dialysis sessions are displayed in the Schedule section.',
                      },
                      {
                        'title': 'Rescheduling Appointment',
                        'content':
                            'Open your scheduled appointment and choose a new available date or time if rescheduling is allowed.',
                      },
                      {
                        'title': 'Canceling Sessions',
                        'content':
                            'Select the appointment you want to cancel and confirm the cancellation.',
                      },
                    ],
                  ),

                  _guideSection(
                    title: 'Donation Drives',
                    subtitle: 'Participating in donation events',
                    items: [
                      {
                        'title': 'Viewing Donation Drives',
                        'content':
                            'Open the Donations tab to view available donation drives and related information.',
                      },
                    ],
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

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EBF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF225E72)),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}
