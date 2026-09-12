import 'package:flutter/material.dart';
import '../../auth/account_auth_controller.dart';
import '../post_detail_page.dart';

class HashtagPage extends StatelessWidget {
  const HashtagPage({super.key, required this.tag, required this.auth});

  final String tag;
  final AccountAuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanTag = tag.replaceAll('#', '');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '#$cleanTag',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: FutureBuilder<List<SocialPost>>(
        future: auth.discoverPosts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final posts = snapshot.data ?? const [];
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tag_rounded, size: 54, color: theme.colorScheme.onSurface.withValues(alpha: .3)),
                  const SizedBox(height: 12),
                  Text('No posts for #$cleanTag', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Be the first to post with this tag.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            itemCount: posts.length,
            itemBuilder: (context, i) {
              final post = posts[i % posts.length];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailPage(post: post, auth: auth),
                    ),
                  );
                },
                child: Image.memory(
                  post.media,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
