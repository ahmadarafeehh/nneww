import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import
import 'package:provider/provider.dart'; // Add this import

// Define color schemes for both themes at top level
class _EditProfileColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color borderColor;
  final Color hintTextColor;
  final Color progressIndicatorColor;

  _EditProfileColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.borderColor,
    required this.hintTextColor,
    required this.progressIndicatorColor,
  });
}

class _EditProfileDarkColors extends _EditProfileColorSet {
  _EditProfileDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          buttonBackgroundColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
          borderColor: const Color(0xFFd9d9d9),
          hintTextColor: const Color(0xFFd9d9d9).withOpacity(0.7),
          progressIndicatorColor: const Color(0xFFd9d9d9),
        );
}

class _EditProfileLightColors extends _EditProfileColorSet {
  _EditProfileLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.white,
          cardColor: Colors.grey[200]!,
          iconColor: Colors.black,
          buttonBackgroundColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
          borderColor: Colors.black,
          hintTextColor: Colors.black.withOpacity(0.7),
          progressIndicatorColor: Colors.black,
        );
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _bioController = TextEditingController();
  Uint8List? _image;
  bool _isLoading = false;
  String? _initialPhotoUrl;
  String? _currentPhotoUrl;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Helper method to get the appropriate color scheme
  _EditProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _EditProfileDarkColors() : _EditProfileLightColors();
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      // Use Supabase instead of Firestore
      final userData =
          await _supabase.from('users').select().eq('uid', uid).single();

      setState(() {
        _bioController.text = userData['bio'] ?? '';
        _initialPhotoUrl = userData['photoUrl'];
        _currentPhotoUrl = _initialPhotoUrl ?? 'default';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Please try again or contact us at ratedly9@gmail.com')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showEditOptions(_EditProfileColorSet colors) {
    bool hasPhoto =
        (_currentPhotoUrl != null && _currentPhotoUrl != 'default') ||
            _image != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPhoto)
                ListTile(
                  leading: Icon(Icons.delete, color: colors.iconColor),
                  title: Text('Remove Picture',
                      style: TextStyle(color: colors.textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _removePhoto();
                  },
                ),
              if (!hasPhoto)
                ListTile(
                  leading: Icon(Icons.photo_library, color: colors.iconColor),
                  title: Text('Choose from Gallery',
                      style: TextStyle(color: colors.textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      Uint8List imageData = await pickedFile.readAsBytes();
      setState(() {
        _image = imageData;
        _currentPhotoUrl = null;
      });
    }
  }

  void _removePhoto() {
    setState(() {
      _image = null;
      _currentPhotoUrl = 'default';
    });
  }

  Future<void> _saveProfile() async {
    // Check bio character limit
    if (_bioController.text.length > 250) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Bio cannot exceed 250 characters. Your bio is ${_bioController.text.length} characters.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      Map<String, dynamic> updatedData = {'bio': _bioController.text};

      if (_image != null) {
        String photoUrl = await StorageMethods().uploadImageToStorage(
          'profilePics',
          _image!,
          false,
        );
        updatedData['photoUrl'] = photoUrl;

        if (_initialPhotoUrl != null && _initialPhotoUrl != 'default') {
          await StorageMethods().deleteImage(_initialPhotoUrl!);
        }
      } else if (_currentPhotoUrl == 'default') {
        if (_initialPhotoUrl != null && _initialPhotoUrl != 'default') {
          await StorageMethods().deleteImage(_initialPhotoUrl!);
        }
        updatedData['photoUrl'] = 'default';
      }

      // Use Supabase instead of Firestore
      await _supabase.from('users').update(updatedData).eq('uid', uid);

      setState(() {
        if (updatedData.containsKey('photoUrl')) {
          _initialPhotoUrl = updatedData['photoUrl'];
        }
        _currentPhotoUrl = _initialPhotoUrl;
        _image = null;
      });

      if (mounted) {
        Navigator.pop(context, {
          'bio': _bioController.text,
          'photoUrl': updatedData['photoUrl'] ?? _initialPhotoUrl
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Please try again or contact us at ratedly9@gmail.com')),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.iconColor),
        title: Text(
          'Edit Profile',
          style: TextStyle(color: colors.textColor),
        ),
        centerTitle: true,
        backgroundColor: colors.backgroundColor,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: () => _showEditOptions(colors),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: colors.cardColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.borderColor,
                            width: 2.0,
                          ),
                        ),
                        child: Stack(
                          children: [
                            ClipOval(
                              child: _image != null
                                  ? Image.memory(
                                      _image!,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    )
                                  : (_currentPhotoUrl != null &&
                                          _currentPhotoUrl != 'default')
                                      ? Image.network(
                                          _currentPhotoUrl!,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Center(
                                            child: Icon(
                                              Icons.account_circle,
                                              size: 96,
                                              color: colors.iconColor,
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Icon(
                                            Icons.account_circle,
                                            size: 96,
                                            color: colors.iconColor,
                                          ),
                                        ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colors.cardColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.backgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 14,
                                  color: colors.iconColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: 'Bio',
                      labelStyle: TextStyle(color: colors.textColor),
                      hintText: 'Write something about yourself...',
                      hintStyle: TextStyle(color: colors.hintTextColor),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      filled: true,
                      fillColor: colors.cardColor,
                    ),
                    style: TextStyle(color: colors.textColor),
                    maxLines: 3,
                    maxLength: 250, // Added 250 character limit
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.buttonBackgroundColor,
                      foregroundColor: colors.buttonTextColor,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
