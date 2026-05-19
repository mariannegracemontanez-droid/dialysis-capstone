import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> privacySections = [
      {
        'title': 'Information We Collect',
        'icon': Icons.storage_rounded,
        'summary': 'Details we need to provide safe and personalized care.',
        'content': [
          {
            'heading': 'Personal Information',
            'body':
                'Your name, email address, phone number, date of birth, and contact details.',
          },
          {
            'heading': 'Medical Information',
            'body':
                'Health records, dialysis session details, lab results, treatment history, and care-related updates.',
          },
          {
            'heading': 'Account Information',
            'body':
                'Login credentials, account preferences, and security settings used to protect your profile.',
          },
          {
            'heading': 'Usage Data',
            'body':
                'App activity, feature usage, and interaction patterns that help us improve the user experience.',
          },
        ],
      },
      {
        'title': 'How We Use Your Information',
        'icon': Icons.device_hub_outlined,
        'summary': 'How your data supports care, scheduling, and updates.',
        'content': [
          {
            'heading': 'Care Services',
            'body':
                'We use your information to provide and maintain dialysis-related services.',
          },
          {
            'heading': 'Appointments',
            'body':
                'Your details help us schedule, manage, and update appointment records.',
          },
          {
            'heading': 'Health Monitoring',
            'body':
                'Medical data may be used to track treatment progress and care outcomes.',
          },
          {
            'heading': 'Communication',
            'body':
                'We may send important health updates, reminders, and service-related notices.',
          },
          {
            'heading': 'Donation Support',
            'body':
                'Information may be used to coordinate donation aid programs and assistance records.',
          },
          {
            'heading': 'Service Improvement',
            'body':
                'We review usage patterns to improve app performance, layout, and user experience.',
          },
        ],
      },
      {
        'title': 'Data Security & Protection',
        'icon': Icons.lock_outline_rounded,
        'summary': 'How we help keep your personal and medical data safe.',
        'content': [
          {
            'heading': 'Secure Data Storage',
            'body':
                'Your medical records are stored using secured systems with controlled access.',
          },
          {
            'heading': 'Restricted Access',
            'body':
                'Only authorized healthcare providers and approved staff can access relevant medical information.',
          },
          {
            'heading': 'Account Protection',
            'body':
                'Security settings help prevent unauthorized access to your account.',
          },
        ],
      },
      {
        'title': 'Information Sharing',
        'icon': Icons.share_outlined,
        'summary': 'When and why your information may be shared.',
        'content': [
          {
            'heading': 'Healthcare Providers',
            'body':
                'Your information may be shared with doctors, clinic staff, and medical personnel involved in your care.',
          },
          {
            'heading': 'Legal Requirements',
            'body':
                'Information may be disclosed when required by law or when necessary to protect safety.',
          },
          {
            'heading': 'With Your Consent',
            'body':
                'We only share additional information when you clearly authorize us to do so.',
          },
        ],
      },
      {
        'title': 'Your Privacy Rights',
        'icon': Icons.shield_outlined,
        'summary': 'Your control over your personal and medical data.',
        'content': [
          {
            'heading': 'Access',
            'body':
                'You may request a copy of your personal and medical information.',
          },
          {
            'heading': 'Correction',
            'body':
                'You may update or correct inaccurate or outdated information.',
          },
          {
            'heading': 'Deletion',
            'body':
                'You may request deletion of your account and related data, subject to applicable requirements.',
          },
          {
            'heading': 'Portability',
            'body':
                'You may request your data in a portable format when available.',
          },
        ],
      },
      {
        'title': 'Cookies & Tracking',
        'icon': Icons.cookie_outlined,
        'summary': 'How app activity may be used to improve your experience.',
        'content': [
          {
            'heading': 'App Activity',
            'body':
                'We may collect basic usage activity to understand how features are used.',
          },
          {
            'heading': 'Preferences',
            'body':
                'Some settings may be stored to keep your app experience consistent.',
          },
          {
            'heading': 'Improvements',
            'body':
                'Usage insights help us identify issues, improve navigation, and enhance app performance.',
          },
        ],
      },
      {
        'title': 'Data Retention',
        'icon': Icons.storage,
        'summary': 'How long certain information may be kept.',
        'content': [
          {
            'heading': 'Medical Records',
            'body':
                'Medical records may be retained for 7 years or as required by applicable healthcare policies.',
          },
          {
            'heading': 'Account Data',
            'body':
                'Account information is retained while your account remains active.',
          },
          {
            'heading': 'Usage Data',
            'body':
                'Usage data may be anonymized and retained for service improvement.',
          },
        ],
      },
      {
        'title': 'Contact Us',
        'icon': Icons.contact_mail_outlined,
        'summary': 'Reach out for questions about your privacy and data.',
        'content': [
          {'heading': 'Email', 'body': 'CureNurture@gmail.com'},
          {'heading': 'Phone Number', 'body': '+6392546987200'},
        ],
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
                          'Privacy Policy',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'How CureNurture protects your information',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7EBEC),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: Color(0xFF2C5F7D),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Our Commitment to Your Privacy',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1F3F52),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          'At CureNurture, we value the privacy of your personal and medical information. This policy explains what we collect, how we use it, and how we help keep your data protected.',
                          style: TextStyle(
                            height: 1.5,
                            fontSize: 13.5,
                            color: Color(0xFF334E5C),
                          ),
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
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
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
                          splashColor: const Color(0xFFEAF6F7),
                          highlightColor: const Color(0xFFEAF6F7),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            18,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF6F7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              section['icon'],
                              color: const Color(0xFF2C5F7D),
                              size: 22,
                            ),
                          ),
                          title: Text(
                            section['title'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              color: Color(0xFF1F2933),
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              section['summary'],
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                                height: 1.3,
                              ),
                            ),
                          ),
                          iconColor: const Color(0xFF2C5F7D),
                          collapsedIconColor: Colors.grey.shade500,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7FAFA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(
                                  section['content'].length,
                                  (index) {
                                    final item = section['content'][index];

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom:
                                            index ==
                                                section['content'].length - 1
                                            ? 0
                                            : 14,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 5,
                                            ),
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF2C8BA3),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item['heading'],
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF243B4A),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  item['body'],
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.45,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
