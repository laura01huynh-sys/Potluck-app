class CommunityReview {
  final String id;
  final String recipeId;
  final String userName;
  final String? userAvatarUrl;
  final int rating; // 1-5 stars
  final String comment;
  final String? imageUrl; // Photo of finished dish
  final DateTime createdDate;
  final int likes; // Number of likes this review received
  final List<ReviewReply> replies; // Replies to this review

  CommunityReview({
    required this.id,
    required this.recipeId,
    required this.userName,
    this.userAvatarUrl,
    required this.rating,
    required this.comment,
    this.imageUrl,
    required this.createdDate,
    this.likes = 0,
    this.replies = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipeId': recipeId,
        'userName': userName,
        'userAvatarUrl': userAvatarUrl,
        'rating': rating,
        'comment': comment,
        'imageUrl': imageUrl,
        'createdDate': createdDate.toIso8601String(),
        'likes': likes,
        'replies': replies.map((r) => r.toJson()).toList(),
      };

  factory CommunityReview.fromJson(Map<String, dynamic> json) {
    return CommunityReview(
      id: json['id'],
      recipeId: json['recipeId'],
      userName: json['userName'],
      userAvatarUrl: json['userAvatarUrl'],
      rating: json['rating'],
      comment: json['comment'],
      imageUrl: json['imageUrl'],
      createdDate: DateTime.parse(json['createdDate']),
      likes: json['likes'] ?? 0,
      replies: (json['replies'] as List<dynamic>?)
              ?.map((r) => ReviewReply.fromJson(r))
              .toList() ??
          [],
    );
  }
}

class ReviewReply {
  final String id;
  final String userName;
  final String comment;
  final DateTime createdDate;
  final int likes;

  ReviewReply({
    required this.id,
    required this.userName,
    required this.comment,
    required this.createdDate,
    this.likes = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userName': userName,
        'comment': comment,
        'createdDate': createdDate.toIso8601String(),
        'likes': likes,
      };

  factory ReviewReply.fromJson(Map<String, dynamic> json) {
    return ReviewReply(
      id: json['id'],
      userName: json['userName'],
      comment: json['comment'],
      createdDate: DateTime.parse(json['createdDate']),
      likes: json['likes'] ?? 0,
    );
  }
}

