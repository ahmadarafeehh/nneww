import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:provider/provider.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/utils/theme_provider.dart'; // Add this import

// Define color schemes for both themes at top level
class _UserListColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;

  _UserListColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
  });
}

class _UserListDarkColors extends _UserListColorSet {
  _UserListDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
        );
}

class _UserListLightColors extends _UserListColorSet {
  _UserListLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.white,
          cardColor: Colors.grey[100]!,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
        );
}

class UserListScreen extends StatelessWidget {
  final String title;
  final List<dynamic> userEntries;

  const UserListScreen({
    Key? key,
    required this.title,
    required this.userEntries,
  }) : super(key: key);

  // Helper method to get the appropriate color scheme
  _UserListColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _UserListDarkColors() : _UserListLightColors();
  }

  List<Map<String, dynamic>> _getValidEntries() {
    // Use a Set to track unique user IDs to prevent duplicates
    final Set<String> uniqueUserIds = {};
    return userEntries
        .map((entry) {
          final userId = entry['userId'] ?? entry['raterUserId'];
          if (userId == null) return null;
          final userIdStr = userId.toString();

          // Skip duplicates
          if (uniqueUserIds.contains(userIdStr)) return null;
          uniqueUserIds.add(userIdStr);

          return {
            'userId': userIdStr,
            'timestamp': entry['timestamp'] ?? DateTime.now(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUser = Provider.of<UserProvider>(context).user;
    final entries = _getValidEntries();

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: colors.backgroundColor,
        body: Center(child: CircularProgressIndicator(color: colors.textColor)),
      );
    }

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text(title, style: TextStyle(color: colors.textColor)),
        backgroundColor: colors.appBarBackgroundColor,
        iconTheme: IconThemeData(color: colors.appBarIconColor),
        centerTitle: true,
      ),
      body: _PaginatedUserList(
        title: title,
        entries: entries,
        colors: colors,
      ),
    );
  }
}

class _PaginatedUserList extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> entries;
  final _UserListColorSet colors;

  const _PaginatedUserList({
    required this.title,
    required this.entries,
    required this.colors,
  });

  @override
  State<_PaginatedUserList> createState() => _PaginatedUserListState();
}

class _PaginatedUserListState extends State<_PaginatedUserList> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _loadedUsers = [];
  final Set<String> _loadedUserIds = {}; // Track loaded user IDs
  bool _isLoading = false;
  bool _hasMore = true;
  int _nextIndex = 0;
  final ScrollController _scrollController = ScrollController();
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    _loadNextBatch();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadNextBatch();
    }
  }

  Future<void> _loadNextBatch() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // Determine batch size (10 initial, then 5)
      final batchSize = _initialLoadComplete ? 5 : 10;
      final startIndex = _nextIndex;
      final endIndex = (_nextIndex + batchSize).clamp(0, widget.entries.length);

      if (startIndex >= endIndex) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        return;
      }

      // Get batch entries and filter out already loaded users
      final batchEntries = widget.entries.sublist(startIndex, endIndex);
      final newBatchEntries = batchEntries.where((entry) {
        final userId = entry['userId'] as String;
        return !_loadedUserIds.contains(userId);
      }).toList();

      // If all users in this batch are already loaded, skip
      if (newBatchEntries.isEmpty) {
        setState(() {
          _nextIndex = endIndex;
          _hasMore = _nextIndex < widget.entries.length;
          _isLoading = false;
        });
        return;
      }

      final batchUserIds =
          newBatchEntries.map((e) => e['userId'] as String).toList();

      // Fetch users in batch from Supabase - using OR condition instead of IN
      String orCondition = batchUserIds.map((id) => 'uid.eq.$id').join(',');

      final usersResponse =
          await _supabase.from('users').select().or(orCondition);

      // Create a map for quick lookup
      final usersMap = {for (var user in usersResponse) user['uid']: user};

      setState(() {
        for (var entry in newBatchEntries) {
          final userId = entry['userId'] as String;

          // Skip if already loaded
          if (_loadedUserIds.contains(userId)) continue;

          final userData =
              usersMap[userId] ?? {'username': 'UserNotFound', 'photoUrl': ''};
          _loadedUsers.add({
            'id': userId,
            'data': userData,
            'entry': entry,
          });
          _loadedUserIds.add(userId); // Mark as loaded
        }

        _nextIndex = endIndex;
        _hasMore = _nextIndex < widget.entries.length;
        _isLoading = false;
        _initialLoadComplete = true;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildListItem(int index) {
    if (index >= _loadedUsers.length) return const SizedBox.shrink();

    final user = _loadedUsers[index];
    final userId = user['id'] as String;
    final userData = user['data'] as Map<String, dynamic>;
    final entry = user['entry'] as Map<String, dynamic>;

    // Handle different timestamp formats
    DateTime timestamp;
    if (entry['timestamp'] is DateTime) {
      timestamp = entry['timestamp'] as DateTime;
    } else if (entry['timestamp'] is String) {
      timestamp = DateTime.parse(entry['timestamp'] as String);
    } else {
      // If no timestamp is provided, use current time (this should be fixed in the parent component)
      timestamp = DateTime.now();
    }

    final isPlaceholder = userData['username'] == 'UserNotFound';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: widget.colors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: widget.colors.cardColor,
          radius: 21,
          backgroundImage: isPlaceholder
              ? null
              : (userData['photoUrl'] != null &&
                      userData['photoUrl'].isNotEmpty &&
                      userData['photoUrl'] != "default")
                  ? NetworkImage(userData['photoUrl'])
                  : null,
          child: (isPlaceholder ||
                  userData['photoUrl'] == null ||
                  userData['photoUrl'].isEmpty ||
                  userData['photoUrl'] == "default")
              ? Icon(
                  Icons.account_circle,
                  size: 42,
                  color: widget.colors.iconColor,
                )
              : null,
        ),
        title: Text(
          isPlaceholder ? 'UserNotFound' : userData['username'] ?? 'Anonymous',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: widget.colors.textColor,
          ),
        ),
        subtitle: Text(
          timeago.format(timestamp),
          style: TextStyle(color: widget.colors.textColor.withOpacity(0.6)),
        ),
        onTap: isPlaceholder
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(uid: userId),
                  ),
                ),
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    if (!_hasMore) return const SizedBox.shrink();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: _isLoading
            ? CircularProgressIndicator(color: widget.colors.textColor)
            : TextButton(
                onPressed: _loadNextBatch,
                child: Text(
                  'Load more',
                  style: TextStyle(
                    color: widget.colors.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_outlined,
              size: 40, color: widget.colors.textColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No data available',
            style: TextStyle(
              color: widget.colors.textColor.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            separatorBuilder: (context, index) =>
                Divider(color: widget.colors.cardColor, height: 1),
            itemCount: _loadedUsers.length,
            itemBuilder: (context, index) => _buildListItem(index),
          ),
        ),
        _buildLoadMoreButton(),
      ],
    );
  }
}
