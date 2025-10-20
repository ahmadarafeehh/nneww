import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

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
  bool _isLoading = true;
  bool _onboardingComplete = false;
  bool _showSkeleton = true;

  @override
  void initState() {
    super.initState();
    _loadProgressively();
  }

  void _loadProgressively() {
    // Show skeleton immediately for instant visual feedback
    setState(() {
      _showSkeleton = true;
    });

    // Process authentication in the next frame without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAuthState();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showSkeleton = false;
        });
      }
    });
  }

  Future<void> _checkAuthState() async {
    // Step 1: Try cache first (fastest - synchronous)
    if (AuthWrapper._cacheInitialized) {
      _currentUser = AuthWrapper._cachedUser;
    } else {
      // Step 2: Try Firebase's synchronous currentUser (very fast)
      _currentUser = _auth.currentUser;
      AuthWrapper._cachedUser = _currentUser;
      AuthWrapper._cacheInitialized = true;
    }

    // Step 3: If no user found synchronously, wait briefly for auth state
    if (_currentUser == null) {
      try {
        final user = await _auth
            .authStateChanges()
            .timeout(const Duration(seconds: 2)) // Short timeout
            .first;
        _currentUser = user;
        AuthWrapper._cachedUser = user;
      } catch (e) {
        // Timeout or error - proceed with null user
        _currentUser = null;
      }
    }

    // Step 4: Check onboarding status if user exists (non-blocking)
    if (_currentUser != null) {
      await _checkOnboardingStatus();
    }
  }

  Future<void> _checkOnboardingStatus() async {
    // Implement your actual onboarding status check here
    // For now, we'll use a minimal delay and assume onboarding is complete
    // Replace this with your actual onboarding check logic

    // Simulate a fast check (remove this in production)
    await Future.delayed(const Duration(milliseconds: 100));

    // Set onboarding complete based on your actual logic
    // Example: Check SharedPreferences, Firestore, or Supabase
    _onboardingComplete = true;
  }

  void _handleOnboardingComplete() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _onboardingComplete = true);
      }
    });
  }

  // Optimized skeleton that renders instantly
  Widget _buildFeedSkeleton(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final skeletonColor = isDarkMode
        ? const Color(0xFF333333).withOpacity(0.6)
        : Colors.grey[300]!.withOpacity(0.6);
    final backgroundColor =
        isDarkMode ? const Color(0xFF121212) : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main skeleton content - using simple widgets for fast rendering
          _buildSkeletonPageView(skeletonColor, backgroundColor),

          // Overlay tabs skeleton
          _buildSkeletonTabs(),

          // Overlay message button skeleton
          _buildSkeletonMessageButton(),
        ],
      ),
    );
  }

  Widget _buildSkeletonPageView(Color skeletonColor, Color backgroundColor) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 2, // Reduced to 2 for faster rendering
      itemBuilder: (ctx, index) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: backgroundColor,
          child: Stack(
            children: [
              // Media content skeleton (full screen) - simple container
              Container(color: skeletonColor),

              // Right side action buttons skeleton
              Positioned(
                bottom: 220,
                right: 16,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: skeletonColor,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: skeletonColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: skeletonColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom overlay skeleton - simplified
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rating section
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: skeletonColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Username and rating
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 18,
                              width: 120,
                              decoration: BoxDecoration(
                                color: skeletonColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Container(
                            height: 32,
                            width: 120,
                            decoration: BoxDecoration(
                              color: skeletonColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeletonTabs() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSkeletonTab('For You'),
            const SizedBox(width: 40),
            _buildSkeletonTab('Following'),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonTab(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 18,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonMessageButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.message,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show skeleton immediately while checking auth (fastest visual feedback)
    // Remove the circle loading state entirely - just use skeleton
    if (_showSkeleton || _isLoading) {
      return _buildFeedSkeleton(context);
    }

    // Auth flow decisions
    if (_currentUser == null) {
      return const GetStartedPage();
    }

    if (_onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    return OnboardingFlow(
      onComplete: _handleOnboardingComplete,
      onError: (error) {
        // Handle onboarding error if needed
        print('Onboarding error: $error');
      },
    );
  }
}
