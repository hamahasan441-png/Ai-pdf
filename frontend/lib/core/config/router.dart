import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/upload/presentation/upload_screen.dart';
import '../../features/document/presentation/document_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/tools/presentation/tools_screen.dart';
import '../../features/tools/presentation/jpg_to_pdf_screen.dart';
import '../../features/tools/presentation/compress_screen.dart';
import '../../features/tools/presentation/pdf_tools_screen.dart';
import '../../features/tools/presentation/pick_edit_screen.dart';
import '../../features/tools/presentation/organize_pages_screen.dart';
import '../../features/tools/presentation/ocr_screen.dart';
import '../../features/tools/presentation/pdf_to_images_screen.dart';
import '../../features/tools/presentation/pdf_stamp_screens.dart';
import '../../features/tools/presentation/rotate_pdf_screen.dart';
import '../../features/tools/presentation/extract_pages_screen.dart';
import '../../features/tools/presentation/pdf_to_text_screen.dart';
import '../../features/tools/presentation/stamp_image_screen.dart';
import '../../features/tools/presentation/delete_pages_screen.dart';
import '../../features/recent/presentation/recent_files_screen.dart';
import '../../features/ai/presentation/ai_chat_screen.dart';
import '../../features/settings/presentation/ai_settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // START AT HOME - no login required (guest mode)
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/upload', builder: (_, __) => const UploadScreen()),
      GoRoute(
        path: '/document/:id',
        builder: (_, state) => DocumentScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/editor/:id',
        builder: (_, state) => EditorScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),

      // Tools hub
      GoRoute(path: '/tools', builder: (_, __) => const ToolsScreen()),

      // Offline tools
      GoRoute(path: '/tools/jpg-to-pdf', builder: (_, __) => const JpgToPdfScreen()),
      GoRoute(path: '/tools/compress', builder: (_, __) => const CompressScreen()),
      GoRoute(path: '/tools/merge', builder: (_, __) => const PdfToolsScreen(mode: PdfToolMode.merge)),
      GoRoute(path: '/tools/split', builder: (_, __) => const PdfToolsScreen(mode: PdfToolMode.split)),
      GoRoute(path: '/tools/pick-edit', builder: (_, __) => const PickEditScreen()),
      GoRoute(path: '/tools/organize', builder: (_, __) => const OrganizePagesScreen()),
      GoRoute(path: '/tools/ocr', builder: (_, __) => const OcrScreen()),
      GoRoute(path: '/tools/pdf-to-images', builder: (_, __) => const PdfToImagesScreen()),
      GoRoute(path: '/tools/watermark', builder: (_, __) => const WatermarkScreen()),
      GoRoute(path: '/tools/page-numbers', builder: (_, __) => const PageNumbersScreen()),
      GoRoute(path: '/tools/rotate', builder: (_, __) => const RotatePdfScreen()),
      GoRoute(path: '/tools/extract-pages', builder: (_, __) => const ExtractPagesScreen()),
      GoRoute(path: '/tools/pdf-to-text', builder: (_, __) => const PdfToTextScreen()),
      GoRoute(path: '/tools/stamp-image', builder: (_, __) => const StampImageScreen()),
      GoRoute(path: '/tools/delete-pages', builder: (_, __) => const DeletePagesScreen()),

      // Recent files (created / edited / saved on device)
      GoRoute(path: '/recent', builder: (_, __) => const RecentFilesScreen()),

      // On-device AI (direct OpenRouter, no backend)
      GoRoute(path: '/ai', builder: (_, __) => const AiChatScreen(mode: AiChatMode.understand)),
      GoRoute(path: '/ai-form', builder: (_, __) => const AiChatScreen(mode: AiChatMode.fillForm)),

      // Dedicated AI settings (key / model / endpoint)
      GoRoute(path: '/settings', builder: (_, __) => const AiSettingsScreen()),
    ],
  );
});
