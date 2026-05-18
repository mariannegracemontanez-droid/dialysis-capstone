import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> privacySections = [
      {
        'title': 'Information we Collect',
        'icon': Icons.storage_rounded,
        'content': '''
          • Personal Information: Name, email address, phone number, date of birth, and contact details

          • Medical Information: Health records, dialysis session data, lab results, and treatment history

          • Account Information: Login credentials, security settings, and preferences

          • Usage Data: App activity, feature usage, and interaction patterns
          ''',
      },
      {
        'title': 'How we use your Information',
        'icon': Icons.device_hub_outlined,
        'content': '''
        • Provide and maintain dialysis care services

        • Schedule and manage appointments

        • Track your health progress and treatment outcomes

        • Communicate important health updates and reminders

        • Coordinate donation aid programs and contributions

        • Improve our services and user experience
        ''',
      },
      {
        'title': 'Data Security & Protection',
        'icon': Icons.lock_outline_rounded,
        'content': '''
          We implement industry-standard security measures:

          • Secure Data Protection
          Your medical records are stored in encrypted databases with restricted access

          • Access Control
          Only authorized healthcare providers can access your medical information
          ''',
      },
      {
        'title': 'Information Sharing',
        'icon': Icons.share_outlined,
        'content': '''
          We only share your information in the following cases:

          • Healthcare Providers:
          With your doctors and medical staff involved in your care

          • Legal Requirements:
          When required by law or to protect safety

          • With Your Consent:
          When you explicitly authorize sharing
          ''',
      },
      {
        'title': 'Your Privacy Rights',
        'icon': Icons.shield_outlined,
        'content': '''
        You have the right to:

        • Access:
        Request a copy of your personal and medical data

        • Correction:
        Update or correct inaccurate information

        • Deletion:
        Request deletion of your account and data

        • Portability:
        Download your data in a portable format
        ''',
      },
      {
        'title': 'Cookies & Tracking',
        'icon': Icons.cookie_outlined,
        'content': '''
          We collect the following types of information:

          • Personal Information:
          Name, email address, phone number, date of birth, and contact details

          • Medical Information:
          Health records, dialysis session data, lab results, and treatment history

          • Account Information:
          Login credentials, security settings, and preferences

          • Usage Data:
          App activity, feature usage, and interaction patterns
          ''',
      },
      {
        'title': 'Data Retention',
        'icon': Icons.storage,
        'content': '''
          We retain your information as follows:

          • Medical Records:
          Retained for 7 years as required by medical record retention laws

          • Account Data:
          Retained while your account is active

          • Usage Data:
          Anonymized and retained for service improvement
          ''',
      },
      {
        'title': 'Contact Us',
        'icon': Icons.contact_mail_outlined,
        'content': '''
          Email: CureNurture@gmail.com

          Phone Number: +6392546987200

          Address: Malanday Valenzuela City
          ''',
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),

      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF2C5F7D),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),

                  const SizedBox(width: 14),

                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      SizedBox(height: 4),

                      Text(
                        'Read our Privacy Policy',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7EBEC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Our Commitment to your Privacy',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          'At CureNurture, we take your privacy seriously. This policy explains how we collect, use, protect, and share your personal and medical information.',
                          style: TextStyle(height: 1.5, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  ...privacySections.map((section) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),

                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),

                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),

                        leading: Icon(
                          section['icon'],
                          color: const Color(0xFF2C8BA3),
                        ),

                        title: Text(
                          section['title'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),

                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              section['content'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
