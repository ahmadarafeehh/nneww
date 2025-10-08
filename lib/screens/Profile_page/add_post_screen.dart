// lib/screens/Profile_page/add_post_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class AddPostScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;
  const AddPostScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  Uint8List? _file;
  bool isLoading = false;
  final TextEditingController _descriptionController = TextEditingController();
  final double _maxFileSize = 2.5 * 1024 * 1024; // 2.5 MB

  Future<void> _selectImage(BuildContext parentContext) async {
    return showDialog<void>(
      context: parentContext,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: mobileBackgroundColor,
          title: Text(
            'Create a Post',
            style: TextStyle(color: primaryColor),
          ),
          children: <Widget>[
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndProcessImage(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text("Cancel", style: TextStyle(color: primaryColor)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // First compression pass (file input)
        Uint8List? compressedImage =
            await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          minWidth: 800,
          minHeight: 800,
          quality: 80,
          format: CompressFormat.jpeg,
        );

        // Additional passes if still too large
        if (compressedImage != null && compressedImage.length > _maxFileSize) {
          compressedImage = await _compressUntilUnderLimit(compressedImage);
        }

        if (compressedImage != null) {
          setState(() => _file = compressedImage);
        } else {
          // Fallback to original bytes if compression failed
          final Uint8List fallback = await pickedFile.readAsBytes();
          setState(() => _file = fallback);
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  Future<Uint8List?> _compressUntilUnderLimit(Uint8List imageBytes) async {
    int quality = 75;
    Uint8List? compressedImage = imageBytes;

    while (quality >= 50 &&
        compressedImage != null &&
        compressedImage.length > _maxFileSize) {
      compressedImage = await FlutterImageCompress.compressWithList(
        compressedImage,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      quality -= 5;
    }
    return compressedImage;
  }

  void _rotateImage() {
    if (_file == null) return;
    try {
      final image = img.decodeImage(_file!);
      if (image == null) return;
      final rotated = img.copyRotate(image, angle: 90);
      setState(() =>
          _file = Uint8List.fromList(img.encodeJpg(rotated, quality: 80)));
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  void postImage(AppUser user) async {
    if (user.uid.isEmpty) {
      if (context.mounted) {
        showSnackBar(context, "User information missing");
      }
      return;
    }

    if (_file == null) {
      if (context.mounted) {
        showSnackBar(context, "Please select an image first.");
      }
      return;
    }

    // Final size check
    if (_file!.length > _maxFileSize) {
      if (context.mounted) {
        showSnackBar(context,
            "Image too large (max 2.5MB). Please choose a smaller image.");
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final String res = await SupabasePostsMethods().uploadPost(
        _descriptionController.text,
        _file!,
        user.uid,
        user.username ?? '',
        user.photoUrl ?? '',
        user.age ?? 0,
        user.gender ?? '',
      );

      if (res == "success" && context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, 'Posted!');
        clearImage();
        widget.onPostUploaded?.call();
        Navigator.pop(context);
      } else if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, 'Error: $res');
      }
    } catch (err) {
      if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, err.toString());
      }
    }
  }

  void clearImage() => setState(() => _file = null);

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final String photoUrl = user.photoUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            clearImage();
            Navigator.pop(context);
          },
        ),
        title: Text('Ratedly', style: TextStyle(color: primaryColor)),
        actions: [
          TextButton(
            onPressed: () => postImage(user),
            child: Text(
              "Post",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
              ),
            ),
          ),
        ],
      ),
      body: _file == null
          ? Center(
              child: IconButton(
                icon: Icon(Icons.upload, color: primaryColor, size: 50),
                onPressed: () => _selectImage(context),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (isLoading)
                    LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: primaryColor.withOpacity(0.2),
                    ),
                  Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: MemoryImage(_file!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blueColor,
                        foregroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: Text('Edit Image',
                              style: TextStyle(color: primaryColor)),
                          backgroundColor: mobileBackgroundColor,
                          children: [
                            SimpleDialogOption(
                              onPressed: () {
                                Navigator.pop(context);
                                _rotateImage();
                              },
                              child: Text('Rotate 90°',
                                  style: TextStyle(color: primaryColor)),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Edit Photo'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: Colors.transparent,
                          backgroundImage:
                              (photoUrl.isNotEmpty && photoUrl != "default")
                                  ? NetworkImage(photoUrl)
                                  : null,
                          child: (photoUrl.isEmpty || photoUrl == "default")
                              ? Icon(Icons.account_circle,
                                  size: 42, color: primaryColor)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _descriptionController,
                            decoration: InputDecoration(
                              hintText: "Write a caption...",
                              hintStyle: TextStyle(
                                  color: primaryColor.withOpacity(0.6)),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(color: primaryColor),
                            maxLines: 3,
                          ),
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
