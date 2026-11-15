import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/flik_state.dart';
import 'screens/main_screen.dart';
import 'services/foreground_receiver_service.dart';
import 'services/storage_service.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      home: const MainScreen(),
    );
  }
}
