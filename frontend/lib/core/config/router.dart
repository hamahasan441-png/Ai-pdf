import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/document/presentation/document_detail_screen.dart';
import '../../features/document/presentation/document_upload_screen.dart';
import '../../features/form/presentation/form_review_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/editor/presentation/pdf_editor_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/upload',
        name: 'upload',
        builder: (context, state) => const DocumentUploadScreen(),
      ),
      GoRoute(
        path: '/document/:id',
        name: 'documentDetail',
        builder: (context, state) => DocumentDetailScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/document/:id/form',
        name: 'formReview',
        builder: (context, state) => FormReviewScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/document/:id/editor',
        name: 'pdfEditor',
        builder: (context, state) => PdfEditorScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
