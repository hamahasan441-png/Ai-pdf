import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/subscription/presentation/paywall_screen.dart';
import '../../features/tools/presentation/tools_screen.dart';
import '../../features/tools/presentation/jpg_to_pdf_screen.dart';
import '../../features/tools/presentation/compress_screen.dart';
import '../../features/tools/presentation/pdf_tools_screen.dart';
import '../../features/tools/presentation/pick_edit_screen.dart';
import '../../features/tools/presentation/smart_fill_screen.dart';
import '../../features/tools/presentation/organize_pages_screen.dart';
import '../../features/tools/presentation/ocr_screen.dart';
import '../../features/tools/presentation/pdf_to_images_screen.dart';
import '../../features/tools/presentation/pdf_stamp_screens.dart';
import '../../features/tools/presentation/rotate_pdf_screen.dart';
import '../../features/tools/presentation/extract_pages_screen.dart';
import '../../features/tools/presentation/pdf_to_text_screen.dart';
import '../../features/tools/presentation/stamp_image_screen.dart';
import '../../features/tools/presentation/delete_pages_screen.dart';
import '../../features/tools/presentation/read_aloud_screen.dart';
import '../../features/tools/presentation/convert_screen.dart';
import '../../features/tools/presentation/import_pdf_screen.dart';
import '../../features/recent/presentation/recent_files_screen.dart';
import '../../features/ai/presentation/ai_chat_screen.dart';
import '../../features/settings/presentation/ai_settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // Fully on-device: no login/account. Home is the entry point.
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),

      // Monetization: Pro paywall (subscriptions + lifetime via Play Billing)
      GoRoute(path: '/paywall', builder: (_, __) => const PaywallScreen()),

      // Tools hub
      GoRoute(path: '/tools', builder: (_, __) => const ToolsScreen()),

      // Offline tools
      GoRoute(path: '/tools/jpg-to-pdf', builder: (_, __) => const JpgToPdfScreen()),
      GoRoute(path: '/tools/compress', builder: (_, __) => const CompressScreen()),
      GoRoute(path: '/tools/merge', builder: (_, __) => const PdfToolsScreen(mode: PdfToolMode.merge)),
      GoRoute(path: '/tools/split', builder: (_, __) => const PdfToolsScreen(mode: PdfToolMode.split)),
      GoRoute(path: '/tools/pick-edit', builder: (_, __) => const PickEditScreen()),
      GoRoute(path: '/tools/smart-fill', builder: (_, __) => const SmartFillScreen()),
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
      GoRoute(path: '/tools/read-aloud', builder: (_, __) => const ReadAloudScreen()),
      GoRoute(path: '/tools/convert', builder: (_, __) => const ConvertScreen()),
      GoRoute(path: '/tools/import-pdf', builder: (_, __) => const ImportPdfScreen()),

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
