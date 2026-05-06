import 'dart:async';
import 'package:flutter/material.dart';
import '../pages/auth/welcome_page.dart'; // adjust path kung nasa ibang folder

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // After 3 seconds, navigate to WelcomePage
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Background image
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/asset/Image/image 4.png'),
            fit: BoxFit.cover, // cover para sakto sa buong screen
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo mo sa gitna
              Image.asset(
                'lib/asset/Image/CureNurture_CircleLogo.png',
                width: 150,
                height: 150,
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                color: Colors.white, // para visible sa background
              ),
            ],
          ),
        ),
      ),
    );
  }
}
