import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/flik_state.dart';
import 'screens/main_screen.dart';
import 'services/foreground_receiver_service.dart';
import 'services/storage_service.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app orientation strictly to Portrait (cannot rotate to landscape)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Android background receive service capability
  ForegroundReceiverService.init();

  // Initialize persistent device storage
  final storage = await StorageService.init();

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const FlikApp(),
    ),
  );
}

class FlikApp extends StatelessWidget {
  const FlikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flik',
      debugShowCheckedModeBanner: false,
      theme: FlikTheme.darkTheme,
      darkTheme: FlikTheme.darkTheme,
      themeMode: ThemeMode.dark,
      // Clamp text scale to 1.0 so enlarged system accessibility font sizes never break layouts
      builder: (context, child) {
        // Keep Flik's typeface fixed while adapting its overall text scale to phone width.
        final widthScale = (MediaQuery.sizeOf(context).width / 390).clamp(0.90, 1.12);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(widthScale),
          ),
          child: child ?? const SizedBox(),
        );
      },
      home: const MainScreen(),
    );
  }
}
