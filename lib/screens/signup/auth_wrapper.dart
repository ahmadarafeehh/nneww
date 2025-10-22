import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  // Simple memory cache for faster subsequent loads
  static User? _cachedUser;
  static bool _cacheInitialized = false;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;
  bool _onboardingComplete = false;
  bool _isLoading = true; // Added loading state

  @override
  void initState() {
    super.initState();
    _initializeInstantly();
  }

  void _initializeInstantly() {
    // INSTANT: Use cached user or Firebase's synchronous currentUser
    if (AuthWrapper._cacheInitialized) {
      _currentUser = AuthWrapper._cachedUser;
    } else {
      _currentUser = _auth.currentUser;
      AuthWrapper._cachedUser = _currentUser;
      AuthWrapper._cacheInitialized = true;
    }

    // Start background auth check without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAuthInBackground();
    });
  }

  Future<void> _checkAuthInBackground() async {
    // Background check for auth state changes
    if (_currentUser == null) {
      try {
        final user = await _auth
            .authStateChanges()
            .timeout(const Duration(seconds: 2))
            .first;

        if (mounted && user != _currentUser) {
          setState(() {
            _currentUser = user;
            AuthWrapper._cachedUser = user;
          });
        }
      } catch (e) {
        // Timeout or error - continue with current state
      }
    }

    // Background check for onboarding status
    if (_currentUser != null && !_onboardingComplete) {
      await _checkOnboardingStatus();
    }

    // Set loading to false when background checks are complete
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkOnboardingStatus() async {
    // Implement your actual onboarding status check here
    // For now, we'll assume onboarding is complete
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
  }

  void _handleOnboardingComplete() {
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show circular loading indicator while checking auth status
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // INSTANT DECISION: Show feed immediately if we have a cached user
    // This provides the fastest possible user experience
    if (_currentUser != null && _onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // If we have a user but onboarding isn't complete, show onboarding
    if (_currentUser != null) {
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {},
      );
    }

    // No user found - show get started page
    return const GetStartedPage();
  }
}
