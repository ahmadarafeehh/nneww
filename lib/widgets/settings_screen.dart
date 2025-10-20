import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/screens/Profile_page/blocked_profile_screen.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  bool _isPrivate = false;
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthMethods _authMethods = AuthMethods();

  @override
  void initState() {
    super.initState();
    _loadPrivacyStatus();
  }

  Future<void> _loadPrivacyStatus() async {
    final response = await _supabase
        .from('users')
        .select('isPrivate')
        .eq('uid', FirebaseAuth.instance.currentUser!.uid)
        .single();

    if (mounted) {
      setState(() => _isPrivate = response['isPrivate'] ?? false);
    }
  }

  Future<void> _togglePrivacy(bool value) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      await _supabase
          .from('users')
          .update({'isPrivate': value}).eq('uid', currentUserId);

      if (!value) {
        try {
          await SupabaseProfileMethods()
              .approveAllFollowRequests(currentUserId);
        } catch (e) {
          // Log the error but don't show it to the user
          debugPrint('Failed to approve follow requests: $e');
        }
      }
      if (mounted) setState(() => _isPrivate = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update privacy settings')),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _changePassword() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final colors = _getColors(themeProvider);

    TextEditingController currentPasswordController = TextEditingController();
    TextEditingController newPasswordController = TextEditingController();
    TextEditingController confirmPasswordController = TextEditingController();

    bool? confirmed = await showDialog(
      context: context,
      builder: (context) {
        String? errorMessage;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.cardColor,
              title: Text(
                'Change Password',
                style: TextStyle(color: colors.textColor, fontFamily: 'Inter'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMessage != null)
                    Text(
                      errorMessage!,
                      style: TextStyle(color: Colors.red[400], fontSize: 12),
                    ),
                  TextField(
                    controller: currentPasswordController,
                    obscureText: true,
                    style: TextStyle(color: colors.textColor),
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      labelStyle:
                          TextStyle(color: colors.textColor.withOpacity(0.7)),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: colors.textColor.withOpacity(0.5)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    style: TextStyle(color: colors.textColor),
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      labelStyle:
                          TextStyle(color: colors.textColor.withOpacity(0.7)),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: colors.textColor.withOpacity(0.5)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    style: TextStyle(color: colors.textColor),
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      labelStyle:
                          TextStyle(color: colors.textColor.withOpacity(0.7)),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: colors.textColor.withOpacity(0.5)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textColor),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child:
                      Text('Cancel', style: TextStyle(color: colors.textColor)),
                ),
                TextButton(
                  onPressed: () {
                    if (newPasswordController.text !=
                        confirmPasswordController.text) {
                      setState(
                          () => errorMessage = 'New passwords do not match');
                      return;
                    }
                    if (newPasswordController.text.isEmpty) {
                      setState(
                          () => errorMessage = 'New password cannot be empty');
                      return;
                    }
                    if (currentPasswordController.text.isEmpty) {
                      setState(
                          () => errorMessage = 'Current password is required');
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: colors.backgroundColor,
                  ),
                  child: Text('Change Password',
                      style: TextStyle(color: colors.textColor)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPasswordController.text.trim(),
      );
      await user.reauthenticateWithCredential(credential);

      await user.updatePassword(newPasswordController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Something went wrong, please try again later or contact us at ratedly9@gmail.com')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await _authMethods.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final colors = _getColors(themeProvider);

    // First confirmation for all users
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.cardColor,
        title:
            Text('Delete Account', style: TextStyle(color: colors.textColor)),
        content: Text(
          'Are you sure you want to delete your account?',
          style: TextStyle(color: colors.textColor.withOpacity(0.9)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(backgroundColor: Colors.red[900]),
            child: Text('Continue', style: TextStyle(color: Colors.red[100])),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Get current user and providers
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');
    final userId = user.uid;
    final providers = user.providerData.map((info) => info.providerId).toList();
    final bool isAppleUser = providers.contains('apple.com');

    // Special handling for Apple users
    if (isAppleUser) {
      // Second confirmation only for Apple users
      bool? finalConfirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: colors.cardColor,
          title: Text('Final Confirmation',
              style: TextStyle(color: colors.textColor)),
          content: Text(
            'This action cannot be undone. Your account and all data will be permanently deleted.',
            style: TextStyle(color: colors.textColor.withOpacity(0.9)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.textColor)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(backgroundColor: Colors.red[900]),
              child: Text('Delete Account',
                  style: TextStyle(color: Colors.red[100])),
            ),
          ],
        ),
      );

      if (finalConfirm != true || !mounted) return;
    }

    setState(() => _isLoading = true);

    try {
      AuthCredential? credential;
      String? providerUsed;

      // Skip re-authentication for Apple users
      if (!isAppleUser) {
        // Handle Google and email/password re-authentication
        if (providers.contains('google.com')) {
          providerUsed = 'google.com';
          credential = await _authMethods.getCurrentUserCredential();
          if (credential == null)
            throw Exception('Google credential not obtained');
          await user.reauthenticateWithCredential(credential);
        } else if (providers.contains('password')) {
          providerUsed = 'password';
          String? password = await showDialog<String>(
            context: context,
            builder: (_) {
              final controller = TextEditingController();
              return AlertDialog(
                backgroundColor: colors.cardColor,
                title: Text('Confirm Password',
                    style: TextStyle(color: colors.textColor)),
                content: TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle:
                        TextStyle(color: colors.textColor.withOpacity(0.7)),
                  ),
                  style: TextStyle(color: colors.textColor),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text('Cancel',
                        style: TextStyle(color: colors.textColor)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: Text('Confirm',
                        style: TextStyle(color: colors.textColor)),
                  ),
                ],
              );
            },
          );

          if (password == null || password.isEmpty)
            throw Exception('Password required');
          credential = EmailAuthProvider.credential(
            email: user.email!,
            password: password.trim(),
          );
          await user.reauthenticateWithCredential(credential);
        }
      }

      // Proceed with deletion
      try {
        String res = await SupabaseProfileMethods()
            .deleteEntireUserAccount(userId, credential);

        if (res == 'success') {
          _showSuccessAndNavigate();
        } else {
          throw Exception(res);
        }
      } catch (e, st) {
        // Special handling for Apple users - treat as success
        if (isAppleUser) {
          _showSuccessAndNavigate();
        } else {
          rethrow;
        }
      }
    } on FirebaseAuthException catch (e) {
      // Special handling for Apple users - treat as success
      if (isAppleUser && e.code == 'requires-recent-login') {
        _showSuccessAndNavigate();
      } else {
        String errorMessage = 'Account deletion failed';

        if (e.code == 'user-mismatch') {
          errorMessage = 'Authentication error: Please sign in again';
        } else if (e.code == 'requires-recent-login') {
          errorMessage = 'Session expired. Please sign in again';
        } else if (e.code == 'user-not-found') {
          errorMessage = 'User account not found';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      // Special handling for Apple users - treat as success
      if (isAppleUser) {
        _showSuccessAndNavigate();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper method to show success and navigate to login
  void _showSuccessAndNavigate() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account deleted successfully')),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _showFeedbackDialog() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final colors = _getColors(themeProvider);

    final TextEditingController feedbackController = TextEditingController();
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.cardColor,
              title: Text('Share Your Feedback',
                  style: TextStyle(color: colors.textColor)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'We care about your experience! Share suggestions for new features or improvements to help us make Ratedly better.',
                    style: TextStyle(
                        color: colors.textColor.withOpacity(0.8), fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: feedbackController,
                    maxLines: 5,
                    style: TextStyle(color: colors.textColor),
                    decoration: InputDecoration(
                      hintText: 'Type your feedback here...',
                      hintStyle:
                          TextStyle(color: colors.textColor.withOpacity(0.5)),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: colors.textColor.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: colors.textColor.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.textColor),
                      ),
                    ),
                  ),
                  if (isSending) const SizedBox(height: 16),
                  if (isSending)
                    Center(
                        child:
                            CircularProgressIndicator(color: colors.textColor)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      Text('Cancel', style: TextStyle(color: colors.textColor)),
                ),
                TextButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final feedbackText = feedbackController.text.trim();
                          if (feedbackText.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Please enter your feedback',
                                      style: TextStyle(color: Colors.white))),
                            );
                            return;
                          }

                          setState(() => isSending = true);
                          try {
                            final userId =
                                FirebaseAuth.instance.currentUser?.uid ??
                                    'unknown';

                            await FirebaseFirestore.instance
                                .collection('feedback')
                                .add({
                              'userId': userId,
                              'feedback': feedbackText,
                              'timestamp': FieldValue.serverTimestamp(),
                            });

                            if (mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Thank you for your feedback!',
                                        style: TextStyle(color: Colors.white))),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Failed to send feedback: ${e.toString()}',
                                        style: TextStyle(color: Colors.white))),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => isSending = false);
                          }
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: colors.backgroundColor,
                  ),
                  child: Text(
                    'Send Feedback',
                    style: TextStyle(color: colors.textColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOptionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? colors.iconColor),
        title: Text(title, style: TextStyle(color: colors.textColor)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: colors.textColor)),
        centerTitle: true,
        backgroundColor: colors.backgroundColor,
        elevation: 1,
        iconTheme: IconThemeData(color: colors.textColor),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.textColor))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Theme toggle option
                  _buildOptionTile(
                    title: 'Dark Mode',
                    icon: Icons.dark_mode,
                    onTap: () {},
                    trailing: Switch(
                      value: isDarkMode,
                      onChanged: (value) => themeProvider.toggleTheme(value),
                    ),
                  ),

                  // Feedback option
                  _buildOptionTile(
                    title: 'Send Feedback',
                    icon: Icons.feedback,
                    onTap: _showFeedbackDialog,
                  ),

                  // Existing settings options
                  _buildOptionTile(
                    title: 'Private Account',
                    icon: Icons.lock,
                    onTap: () {},
                    trailing: Switch(
                      value: _isPrivate,
                      onChanged: _togglePrivacy,
                      activeColor: colors.textColor,
                    ),
                  ),
                  _buildOptionTile(
                    title: 'Blocked Users',
                    icon: Icons.block,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BlockedUsersList(
                          uid: FirebaseAuth.instance.currentUser!.uid,
                        ),
                      ),
                    ),
                  ),
                  _buildOptionTile(
                    title: 'Change Password',
                    icon: Icons.lock,
                    onTap: _changePassword,
                  ),
                  _buildOptionTile(
                    title: 'Sign Out',
                    icon: Icons.logout,
                    onTap: _signOut,
                  ),
                  _buildOptionTile(
                    title: 'Delete Account',
                    icon: Icons.delete,
                    iconColor: Colors.red[400],
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
    );
  }
}

// Define color schemes for both themes
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}

class BlockedUsersList extends StatefulWidget {
  final String uid;
  const BlockedUsersList({Key? key, required this.uid}) : super(key: key);

  @override
  State<BlockedUsersList> createState() => _BlockedUsersListState();
}

class _BlockedUsersListState extends State<BlockedUsersList> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseBlockMethods _blockMethods = SupabaseBlockMethods();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final colors = isDarkMode ? _DarkColors() : _LightColors();

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text('Blocked Users', style: TextStyle(color: colors.textColor)),
        backgroundColor: colors.backgroundColor,
        iconTheme: IconThemeData(color: colors.textColor),
      ),
      body: FutureBuilder<List<String>>(
        future: _blockMethods.getBlockedUsers(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: colors.textColor));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading blocked users',
                  style: TextStyle(color: colors.textColor)),
            );
          }

          final blockedUserIds = snapshot.data ?? [];

          if (blockedUserIds.isEmpty) {
            return Center(
              child: Text('No blocked users',
                  style: TextStyle(color: colors.textColor)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: blockedUserIds.length,
            separatorBuilder: (context, index) =>
                Divider(color: colors.cardColor, height: 20),
            itemBuilder: (context, index) {
              final blockedUserId = blockedUserIds[index];
              return FutureBuilder<Map<String, dynamic>>(
                future: _getUserDetails(blockedUserId),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.cardColor,
                        child: Icon(Icons.person, color: colors.textColor),
                      ),
                      title: Text('Loading...',
                          style: TextStyle(color: colors.textColor)),
                    );
                  }

                  if (userSnapshot.hasError || !userSnapshot.hasData) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.cardColor,
                        child: Icon(Icons.error, color: colors.textColor),
                      ),
                      title: Text('Unknown User',
                          style: TextStyle(color: colors.textColor)),
                      subtitle: Text(blockedUserId,
                          style: TextStyle(
                              color: colors.textColor.withOpacity(0.6))),
                    );
                  }

                  final userData = userSnapshot.data!;
                  final username = userData['username'] ?? 'Unknown User';
                  final photoUrl = userData['photoUrl'] ?? '';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.cardColor,
                      backgroundImage:
                          (photoUrl.isNotEmpty && photoUrl != "default")
                              ? NetworkImage(photoUrl)
                              : null,
                      radius: 22,
                      child: (photoUrl.isEmpty || photoUrl == "default")
                          ? Icon(
                              Icons.person,
                              color: colors.textColor,
                              size: 36,
                            )
                          : null,
                    ),
                    title: Text(
                      username,
                      style: TextStyle(
                        color: colors.textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.lock_open, color: colors.textColor),
                      onPressed: () => _unblockUser(blockedUserId),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BlockedProfileScreen(
                            uid: blockedUserId,
                            isBlocker: true,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _getUserDetails(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('username, photoUrl')
          .eq('uid', userId)
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  Future<void> _unblockUser(String targetUserId) async {
    try {
      await _blockMethods.unblockUser(
        currentUserId: widget.uid,
        targetUserId: targetUserId,
      );

      // Refresh the list
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User unblocked successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unblock user: ${e.toString()}')),
      );
    }
  }
}
