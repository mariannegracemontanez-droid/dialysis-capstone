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
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2933),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            color: Colors.black54,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),

        ...items.map((item) {
          IconData itemIcon = Icons.info_outline;

          final title = item['title']!.toLowerCase();

          if (title.contains('account')) {
            itemIcon = Icons.person_add_alt_1_outlined;
          } else if (title.contains('profile')) {
            itemIcon = Icons.badge_outlined;
          } else if (title.contains('navigating')) {
            itemIcon = Icons.explore_outlined;
          } else if (title.contains('notification')) {
            itemIcon = Icons.notifications_none_outlined;
          } else if (title.contains('booking')) {
            itemIcon = Icons.calendar_month_outlined;
          } else if (title.contains('upcoming')) {
            itemIcon = Icons.event_available_outlined;
          } else if (title.contains('rescheduling')) {
            itemIcon = Icons.calendar_month_outlined;
          } else if (title.contains('canceling')) {
            itemIcon = Icons.event_busy_outlined;
          } else if (title.contains('recommender')) {
            itemIcon = Icons.recommend_outlined;
          } else if (title.contains('recommended')) {
            itemIcon = Icons.local_hospital_outlined;
          } else if (title.contains('checking')) {
            itemIcon = Icons.location_city_outlined;
          } else if (title.contains('choosing')) {
            itemIcon = Icons.check_circle_outline;
          } else if (title.contains('no center')) {
            itemIcon = Icons.search_off_outlined;
          }

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
              data: ThemeData().copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F2F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    itemIcon,
                    color: const Color(0xFF225E72),
                    size: 21,
                  ),
                ),
                title: Text(
                  item['title']!,
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
                      item['content']!,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 22),
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
                    childAspectRatio: 1.12,
                    children: const [
                      _QuickAccessCard(
                        icon: Icons.book_outlined,
                        title: 'Getting Started',
                        subtitle: 'Basic app setup and navigation',
                      ),
                      _QuickAccessCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'Appointments',
                        subtitle: 'Book and manage dialysis sessions',
                      ),
                      _QuickAccessCard(
                        icon: Icons.recommend_outlined,
                        title: 'Center Recommender',
                        subtitle: 'Find suitable dialysis centers',
                      ),
                      _QuickAccessCard(
                        icon: Icons.medical_information_outlined,
                        title: 'Medical Records',
                        subtitle: 'View health and treatment history',
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
                    title: 'Center Recommender',
                    subtitle:
                        'Finding dialysis centers that may fit your needs',
                    items: [
                      {
                        'title': 'Using the Center Recommender',
                        'content':
                            'Open the Center Recommender section to view dialysis centers suggested based on available clinic information, location, and service details.',
                      },
                      {
                        'title': 'Understanding Recommended Centers',
                        'content':
                            'Recommended centers may show helpful details such as clinic name, location, contact number, requirements, and other information that can help you compare options.',
                      },
                      {
                        'title': 'Checking Center Details',
                        'content':
                            'Review each center carefully before choosing. Check important information such as address, contact details, clinic availability, and requirements if provided.',
                      },
                      {
                        'title': 'Choosing a Suitable Center',
                        'content':
                            'Select a center that best matches your treatment needs, travel convenience, and clinic availability.',
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF225E72), size: 22),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2933),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.black54,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
