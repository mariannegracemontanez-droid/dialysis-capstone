import 'package:flutter/material.dart';

class MoreDetailsPage extends StatelessWidget {
  const MoreDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFF8FAFB);
    const cardColor = Color(0xFFE0F7F9);
    const headerColor = Color(0xFF1F5E7D);
    const bodyColor = Color(0xFF343A40);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F5E7D)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'lib/assets/image/CureNurture_logo.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Text(
              'Cure Nurture',
              style: TextStyle(
                color: Color(0xFF1F5E7D),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDetailCard(
                title: 'Our Purpose',
                body:
                    'CureNurture was created to bridge the gap between patients who urgently need financial assistance and the specialized care they deserve. Our platform connects donors to real-life impact.',
                bullets: const [
                  'Financial support for Dialysis sessions',
                  'Access to medical supplies',
                  'Transportation assistance',
                  'Emergency medication',
                ],
                cardColor: cardColor,
                headerColor: headerColor,
                bodyColor: bodyColor,
              ),
              const SizedBox(height: 20),
              _buildDetailCard(
                title: 'Why We Do It',
                body:
                    'Kidney failure is a life-altering reality for thousands. By providing consistent support, we extend lives and offer hope to families struggling with the high costs of maintenance care. Your generosity brings stability and healing.',
                cardColor: cardColor,
                headerColor: headerColor,
                bodyColor: bodyColor,
              ),
              const SizedBox(height: 20),
              _buildDetailCard(
                title: 'Our Vision',
                body:
                    'To create a world where every dialysis patient has access to essential care regardless of their financial status. We envision a community-driven healthcare support system where survival never depends on money.',
                cardColor: cardColor,
                headerColor: headerColor,
                bodyColor: bodyColor,
              ),
              const SizedBox(height: 20),
              _buildDetailCard(
                title: 'Transparency & Trust',
                body:
                    'Every peso donated is accounted for. We provide public proof of distribution (verified by our Super Admin) to ensure our donors see exactly how their contributions are saving lives.',
                cardColor: cardColor,
                headerColor: headerColor,
                bodyColor: bodyColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required String body,
    required Color cardColor,
    required Color headerColor,
    required Color bodyColor,
    List<String>? bullets,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: headerColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: TextStyle(color: bodyColor, fontSize: 16, height: 1.7),
          ),
          if (bullets != null && bullets.isNotEmpty) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: bullets
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '• $item',
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: 16,
                          height: 1.7,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
