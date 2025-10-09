// lib/screens/Profile_page/add_post_screen.dart
import 'dart:typed_data';
import 'dart:io';
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
import 'package:video_trimmer/video_trimmer.dart';

class AddPostScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;
  const AddPostScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  Uint8List? _file;
  File? _videoFile;
  bool isLoading = false;
  bool _isVideo = false;
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();
  final double _maxFileSize = 2.5 * 1024 * 1024;
  final double _maxVideoSize = 50 * 1024 * 1024;

  // Video trimming variables
  final Trimmer _trimmer = Trimmer();
  bool _isTrimming = false;
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  @override
  void dispose() {
    _trimmer.dispose();
    _descriptionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _selectMedia(BuildContext parentContext) async {
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
              child: Text('Choose Image from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndProcessImage(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Video from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickVideoFromGallery();
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
      setState(() {
        _isVideo = false;
        isLoading = true;
        _isTrimming = false;
        _videoFile = null;
      });

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        Uint8List? compressedImage =
            await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          minWidth: 800,
          minHeight: 800,
          quality: 80,
          format: CompressFormat.jpeg,
        );

        if (compressedImage != null && compressedImage.length > _maxFileSize) {
          compressedImage = await _compressUntilUnderLimit(compressedImage);
        }

        if (compressedImage != null) {
          setState(() {
            _file = compressedImage;
            isLoading = false;
          });
        } else {
          final Uint8List fallback = await pickedFile.readAsBytes();
          setState(() {
            _file = fallback;
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      setState(() {
        _isVideo = true;
        isLoading = true;
        _file = null;
      });

      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);

        // Check video size
        if (await videoFile.length() > _maxVideoSize) {
          if (context.mounted) {
            showSnackBar(context,
                'Video too large (max 50MB). Please choose a shorter video.');
          }
          setState(() => isLoading = false);
          return;
        }

        // Store the original video file and go directly to trimming
        _videoFile = videoFile;

        // Load video into trimmer
        _loadVideo();

        setState(() {
          _isTrimming = true;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(context, 'Failed to pick video: $e');
      }
    }
  }

  void _loadVideo() {
    if (_videoFile != null) {
      _trimmer.loadVideo(videoFile: _videoFile!);
    }
  }

  Future<String?> _trimVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    String? trimmedPath;

    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (String? value) {
        setState(() {
          _progressVisibility = false;
          trimmedPath = value;
        });
      },
    );

    return trimmedPath;
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
    if (_file == null || _isVideo) return;

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

  void postMedia(AppUser user) async {
    if (user.uid.isEmpty) {
      if (context.mounted) {
        showSnackBar(context, "User information missing");
      }
      return;
    }

    if (!_isVideo && _file == null) {
      if (context.mounted) {
        showSnackBar(context, "Please select media first.");
      }
      return;
    }

    if (_isVideo && _videoFile == null) {
      if (context.mounted) {
        showSnackBar(context, "Please select a video first.");
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final String res;

      if (_isVideo) {
        // If we're in trimming mode, trim the video first
        if (_isTrimming) {
          setState(() => _progressVisibility = true);
          final String? trimmedPath = await _trimVideo();
          setState(() => _progressVisibility = false);

          if (trimmedPath == null) {
            if (context.mounted) {
              showSnackBar(context, 'Failed to trim video');
            }
            setState(() => isLoading = false);
            return;
          }

          _videoFile = File(trimmedPath);
        }

        res = await SupabasePostsMethods().uploadVideoPostFromFile(
          _descriptionController.text,
          _videoFile!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      } else {
        res = await SupabasePostsMethods().uploadPost(
          _descriptionController.text,
          _file!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      }

      if (res == "success" && context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, _isVideo ? 'Video Posted!' : 'Posted!');
        clearMedia();
        widget.onPostUploaded?.call();
        Navigator.pop(context);
      } else if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, 'Error: $res');
      }
    } catch (err) {
      setState(() => isLoading = false);
      if (context.mounted) {
        showSnackBar(context, err.toString());
      }
    }
  }

  void clearMedia() {
    setState(() {
      _file = null;
      _videoFile = null;
      _isVideo = false;
      _isTrimming = false;
      _isPlaying = false;
      _progressVisibility = false;
      _descriptionController.clear();
    });
  }

  Widget _buildVideoTrimmer(AppUser user) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            // Go directly back to profile when back button is pressed
            clearMedia();
            Navigator.pop(context);
          },
        ),
        title: Text('Trim Video', style: TextStyle(color: primaryColor)),
        actions: [
          TextButton(
            onPressed: () => postMedia(user),
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
      body: Column(
        children: [
          // Video Trimmer Section
          Expanded(
            child: Container(
              padding: EdgeInsets.only(bottom: 16.0),
              color: Colors.black,
              child: Column(
                children: <Widget>[
                  Visibility(
                    visible: _progressVisibility,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.red,
                    ),
                  ),
                  Expanded(
                    child: VideoViewer(trimmer: _trimmer),
                  ),
                  Center(
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 50.0,
                      viewerWidth: MediaQuery.of(context).size.width,
                      maxVideoLength: const Duration(seconds: 20),
                      onChangeStart: (value) => _startValue = value,
                      onChangeEnd: (value) => _endValue = value,
                      onChangePlaybackState: (value) =>
                          setState(() => _isPlaying = value),
                    ),
                  ),
                  TextButton(
                    child: _isPlaying
                        ? Icon(
                            Icons.pause,
                            size: 80.0,
                            color: Colors.white,
                          )
                        : Icon(
                            Icons.play_arrow,
                            size: 80.0,
                            color: Colors.white,
                          ),
                    onPressed: () async {
                      bool playbackState = await _trimmer.videoPlaybackControl(
                        startValue: _startValue,
                        endValue: _endValue,
                      );
                      setState(() {
                        _isPlaying = playbackState;
                      });
                    },
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Caption Input Section
          Container(
            color: mobileBackgroundColor,
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.transparent,
                  backgroundImage: (user.photoUrl?.isNotEmpty == true &&
                          user.photoUrl != "default")
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: (user.photoUrl?.isEmpty == true ||
                          user.photoUrl == "default")
                      ? Icon(Icons.account_circle,
                          size: 40, color: primaryColor)
                      : null,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _descriptionController,
                    focusNode: _captionFocusNode,
                    decoration: InputDecoration(
                      hintText: "Write a caption...",
                      hintStyle:
                          TextStyle(color: primaryColor.withOpacity(0.6)),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    style: TextStyle(color: primaryColor),
                    maxLines: 3,
                  ),
                ),
                SizedBox(width: 8),
                // OK Button to dismiss keyboard
                if (_captionFocusNode.hasFocus)
                  TextButton(
                    onPressed: _dismissKeyboard,
                    child: Text(
                      "OK",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    // If we're trimming a video, show the trimmer interface directly
    if (_isTrimming) {
      return _buildVideoTrimmer(user);
    }

    // Main screen - only for images or initial selection
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            clearMedia();
            Navigator.pop(context);
          },
        ),
        title: Text('Ratedly', style: TextStyle(color: primaryColor)),
        actions: [
          // Only show Post button for images (videos go directly to trimming)
          if (_file != null && !_isVideo)
            TextButton(
              onPressed: () => postMedia(user),
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
      body: _file == null && _videoFile == null
          ? Center(
              child: IconButton(
                icon: Icon(Icons.upload, color: primaryColor, size: 50),
                onPressed: () => _selectMedia(context),
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
                  // Only show image preview (videos go directly to trimming)
                  if (!_isVideo && _file != null)
                    Container(
                      height: MediaQuery.of(context).size.height * 0.5,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: primaryColor),
                      ),
                      child: Image.memory(
                        _file!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (!_isVideo && _file != null)
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
                          backgroundImage: (user.photoUrl?.isNotEmpty == true &&
                                  user.photoUrl != "default")
                              ? NetworkImage(user.photoUrl!)
                              : null,
                          child: (user.photoUrl?.isEmpty == true ||
                                  user.photoUrl == "default")
                              ? Icon(Icons.account_circle,
                                  size: 42, color: primaryColor)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _descriptionController,
                            focusNode: _captionFocusNode,
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
                        SizedBox(width: 8),
                        // OK Button to dismiss keyboard
                        if (_captionFocusNode.hasFocus)
                          TextButton(
                            onPressed: _dismissKeyboard,
                            child: Text(
                              "OK",
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
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
