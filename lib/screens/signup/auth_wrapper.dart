import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;
  bool _isLoading = true;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Get initial auth state
      final user = await _auth
          .authStateChanges()
          .timeout(const Duration(seconds: 10))
          .first;

      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    } catch (e) {
      print(' Auth initialization error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _handleOnboardingComplete() {
    print(' Onboarding completed successfully');
    // Use a post-frame callback to safely update state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _onboardingComplete = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingScreen('Checking authentication...');
    }

    if (_currentUser == null) {
      return const GetStartedPage();
    }

    if (_onboardingComplete) {
      // Return your main app screen after onboarding
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    return OnboardingFlow(
      onComplete: _handleOnboardingComplete,
      onError: (error) {
        print(' Onboarding error: $error');
        // Handle error if needed
      },
    );
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
