import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of [FirebaseService.syncProfileWithAuth]. Gives UI what it needs to update profile + follower state.
class SyncProfileResult {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final int followerCount;
  final Set<String> followingIds;

  const SyncProfileResult({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.followerCount,
    required this.followingIds,
  });
}

/// Firebase Auth + Firestore helpers for profiles, recipes, follows.
/// Firestore collections:
///   - profiles/{uid}  (username, display_name, avatar_url, made_count, shared_count, follower_count)
///   - recipes/{id}    (user_id, title, image_url, prep_time, created_at)
///   - follows/{auto}  (follower_id, following_id)
class FirebaseService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  static bool get isSignedIn => currentUser != null;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password.
  static Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Sign up with email and password. Creates a Firestore profile doc automatically.
  static Future<void> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user?.uid;
    if (uid == null) return;
    final local = email.split('@').first;
    final fallbackName = local
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    await _db.collection('profiles').doc(uid).set({
      'username': 'user_${uid.substring(0, 8)}',
      'display_name': fallbackName,
      'avatar_url': null,
      'made_count': 0,
      'shared_count': 0,
      'follower_count': 0,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Sign out.
  static Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Returns a user-friendly message for auth errors (sign in, sign up, etc.).
  /// Use in WelcomeScreen, SignUpSheetContent, Chef Identity, password reset, etc.
  static String? friendlyAuthError(Object e) {
    final msg = e.toString();
    if (msg.contains('Invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (msg.contains('User already registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('Password should be at least')) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('Unable to validate email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('Email rate limit exceeded')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('Connection timed out') ||
        msg.contains('TimeoutException')) {
      return 'Connection timed out. Check your network and try again.';
    }
    return msg
        .replaceFirst('AuthException: ', '')
        .replaceFirst('Exception: ', '');
  }

  /// Result of syncing current auth state with Firestore profile (for UI).
  /// Use in MainNavigation / any widget that holds UserProfile and follower state.
  static Future<SyncProfileResult?> syncProfileWithAuth() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final profile = await getProfile(user.uid);
      if (profile == null) return null;
      final username =
          profile['username'] as String? ?? user.email ?? 'User';
      final avatarUrl = profile['avatar_url'] as String?;
      final followerCount = profile['follower_count'] as int? ?? 0;
      final followingIds = await getFollowingIds();
      return SyncProfileResult(
        userId: user.uid,
        userName: username,
        avatarUrl: avatarUrl,
        followerCount: followerCount,
        followingIds: followingIds,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetch profile for [userId]. Returns null if not found.
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final doc = await _db.collection('profiles').doc(userId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// Update profile stats (made_count, shared_count).
  static Future<void> updateProfileStats({
    required String userId,
    int? madeCount,
    int? sharedCount,
  }) async {
    if (currentUser?.uid != userId) return;
    final updates = <String, dynamic>{};
    if (madeCount != null) updates['made_count'] = madeCount;
    if (sharedCount != null) updates['shared_count'] = sharedCount;
    if (updates.isEmpty) return;
    await _db.collection('profiles').doc(userId).update(updates);
  }

  /// Update username (@handle), display name, and/or avatar_url.
  static Future<void> updateProfile({
    required String userId,
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    if (currentUser?.uid != userId) return;
    final updates = <String, dynamic>{};
    if (username != null) updates['username'] = username;
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;
    await _db.collection('profiles').doc(userId).update(updates);
  }

  /// Follow another user. No-op if already following or self-follow.
  static Future<void> follow(String followingId) async {
    final uid = currentUser?.uid;
    if (uid == null || uid == followingId) return;
    final existing = await _db
        .collection('follows')
        .where('follower_id', isEqualTo: uid)
        .where('following_id', isEqualTo: followingId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    await _db.collection('follows').add({
      'follower_id': uid,
      'following_id': followingId,
      'created_at': FieldValue.serverTimestamp(),
    });
    await _db.collection('profiles').doc(followingId).update({
      'follower_count': FieldValue.increment(1),
    });
  }

  /// Unfollow another user.
  static Future<void> unfollow(String followingId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    final snap = await _db
        .collection('follows')
        .where('follower_id', isEqualTo: uid)
        .where('following_id', isEqualTo: followingId)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
    if (snap.docs.isNotEmpty) {
      await _db.collection('profiles').doc(followingId).update({
        'follower_count': FieldValue.increment(-1),
      });
    }
  }

  /// Get list of user IDs the current user follows.
  static Future<Set<String>> getFollowingIds() async {
    final uid = currentUser?.uid;
    if (uid == null) return {};
    try {
      final snap = await _db
          .collection('follows')
          .where('follower_id', isEqualTo: uid)
          .get();
      return snap.docs
          .map((d) => d['following_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Check if [id] looks like a Firebase UID (20–28 alphanumeric chars).
  static bool isFirebaseUserId(String? id) {
    if (id == null || id.length < 20 || id.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
  }

  /// Insert a shared recipe.
  static Future<String?> insertRecipe({
    required String title,
    String? imageUrl,
    int prepTime = 0,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    try {
      final ref = await _db.collection('recipes').add({
        'user_id': uid,
        'title': title,
        'image_url': imageUrl,
        'prep_time': prepTime,
        'created_at': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  /// Delete the current user's account and their data.
  static Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    final uid = user.uid;
    try {
      final follows = await _db
          .collection('follows')
          .where('follower_id', isEqualTo: uid)
          .get();
      for (final doc in follows.docs) {
        await doc.reference.delete();
      }
      final followers = await _db
          .collection('follows')
          .where('following_id', isEqualTo: uid)
          .get();
      for (final doc in followers.docs) {
        await doc.reference.delete();
      }
      final recipes = await _db
          .collection('recipes')
          .where('user_id', isEqualTo: uid)
          .get();
      for (final doc in recipes.docs) {
        await doc.reference.delete();
      }
      await _db.collection('profiles').doc(uid).delete();
      await user.delete();
    } catch (_) {
      await signOut();
    }
  }
}
