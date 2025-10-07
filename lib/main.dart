import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/services/analytics_service.dart';
import 'package:Ratedly/services/notification_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const bool useDebugHome = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyAFpbPiK6u8KMIfob0pu44ca8YLGYKJHDk",
          authDomain: "rateapp-3b78e.firebaseapp.com",
          projectId: "rateapp-3b78e",
          storageBucket: "rateapp-3b78e.appspot.com",
          messagingSenderId: "411393947451",
          appId: "1:411393947451:web:62e5c1b57a3c7a66da691e",
          measurementId: "G-JSXVSH5PB8",
        ),
      );
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } else {
      await Firebase.initializeApp();
    }

    print(
        'Firebase initialized. Current user: ${FirebaseAuth.instance.currentUser?.uid}');

    // Initialize Mobile Ads SDK
    await MobileAds.instance.initialize();

    // Initialize Supabase
    await Supabase.initialize(
      url: 'https://tbiemcbqjjjsgumnjlqq.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiaWVtY2Jxampqc2d1bW5qbHFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMTQ2NjQsImV4cCI6MjA2OTg5MDY2NH0.JAgFU3fDBGAlMFuHQDqiu35GFe-QYMJfoaIc3mI26yM',
    );

    print(
        'Supabase initialized. Current user: ${Supabase.instance.client.auth.currentUser?.id}');

    // Initialize services
    await AnalyticsService.init();
    await NotificationService().init();

    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  } catch (e, st) {
    print('Initialization failed: $e\n$st');
    ErrorWidget.builder = (details) => Scaffold(
          body: Center(
            child: Text('Critical error: ${details.exception}'),
          ),
        );
    runApp(const ErrorApp());
  }
}

// Simple GDPR compliance without complex AdMob consent that causes build issues
class AdConsentManager {
  static bool _consentGiven = false;
  static bool _isEEAUser = false;

  static Future<void> initialize() async {
    // Simple implementation - you can replace this with your own logic
    // For now, we'll assume consent is given and user is not in EEA
    _consentGiven = true;
    _isEEAUser = false;
    print('Ad consent manager initialized');
  }

  static bool get shouldShowConsent => _isEEAUser && !_consentGiven;

  static Future<void> showConsentDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ad Personalization'),
        content: const Text(
          'We use ads to support our app. You can choose whether to see personalized ads based on your interests.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _consentGiven = false;
              Navigator.pop(context);
            },
            child: const Text('Non-Personalized'),
          ),
          TextButton(
            onPressed: () {
              _consentGiven = true;
              Navigator.pop(context);
            },
            child: const Text('Personalized'),
          ),
        ],
      ),
    );
  }

  static Future<void> showPrivacyOptions(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Settings'),
        content: const Text(
          'Manage your ad personalization preferences. You can change these settings at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              _consentGiven = !_consentGiven;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_consentGiven
                      ? 'Personalized ads enabled'
                      : 'Non-personalized ads enabled'),
                ),
              );
            },
            child: Text(_consentGiven
                ? 'Disable Personalized Ads'
                : 'Enable Personalized Ads'),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        Provider(create: (_) => SupabaseProfileMethods()),
        Provider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ratedly',
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.grey[100],
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey[600],
            selectedLabelStyle: const TextStyle(color: primaryColor),
            unselectedLabelStyle: TextStyle(color: Colors.grey[600]),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: mobileBackgroundColor,
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: mobileBackgroundColor,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey[600],
            selectedLabelStyle: const TextStyle(color: primaryColor),
            unselectedLabelStyle: TextStyle(color: Colors.grey[600]),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
          ),
        ),
        themeMode: themeProvider.themeMode,
        home: useDebugHome
            ? const DebugHome()
            : const OrientationPersistentWrapper(),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 20),
              Text('App initialization failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                    'Please check your internet connection and try again.',
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrientationPersistentWrapper extends StatefulWidget {
  const OrientationPersistentWrapper({super.key});

  @override
  State<OrientationPersistentWrapper> createState() =>
      _OrientationPersistentWrapperState();
}

class _OrientationPersistentWrapperState
    extends State<OrientationPersistentWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setSystemUIOverlayStyle();
    // Initialize our simple consent manager
    AdConsentManager.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _setSystemUIOverlayStyle();
    super.didChangeMetrics();
  }

  void _setSystemUIOverlayStyle() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          isDarkMode ? const Color(0xFF121212) : Colors.white,
      systemNavigationBarIconBrightness:
          isDarkMode ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _setSystemUIOverlayStyle());
    return const AuthWrapper();
  }
}

class DebugHome extends StatefulWidget {
  const DebugHome({Key? key}) : super(key: key);

  @override
  State<DebugHome> createState() => _DebugHomeState();
}

class _DebugHomeState extends State<DebugHome> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String _msg = 'starting...';

  @override
  void initState() {
    super.initState();
    _checkSupabase();
  }

  Future<void> _checkSupabase() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      debugPrint('DebugHome: firebase currentUser = $firebaseUser');
      setState(() => _msg = 'Firebase UID: ${firebaseUser?.uid ?? "null"}');

      final resp =
          await _supabase.from('posts').select('postId').limit(1).maybeSingle();

      debugPrint('Supabase response: $resp');

      setState(
          () => _msg = 'Supabase query result: ${resp?.toString() ?? "null"}');
    } catch (e, st) {
      debugPrint('DebugHome error: $e\n$st');
      setState(() => _msg = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Supabase + Firebase'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.privacy_tip),
            onPressed: () => AdConsentManager.showPrivacyOptions(context),
            tooltip: 'Manage Ad Preferences',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => AdConsentManager.showPrivacyOptions(context),
                icon: const Icon(Icons.settings),
                label: const Text('Manage Ad Consent Preferences'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
