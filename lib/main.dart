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

    // 1. INITIALIZE ADMOB CONSENT (GDPR COMPLIANCE)
    await _initializeAdMobConsent();

    // 2. Initialize Mobile Ads SDK AFTER consent
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

// GDPR COMPLIANCE: AdMob Consent Initialization
// GDPR COMPLIANCE: AdMob Consent Initialization
Future<void> _initializeAdMobConsent() async {
  print('Initializing AdMob GDPR consent...');

  // PRODUCTION: No debug settings
  final params = ConsentRequestParameters();

  // Request consent information update
  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
        () async {
      // Consent info updated successfully
      print('Consent info updated successfully');

      // Check if consent form is available (user is in EEA/UK/Switzerland)
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        print('Consent form required - loading form...');

        // Load and show the GDPR consent form
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (error != null) {
            // Handle errors that occurred while loading the consent form
            print('Error showing consent form: ${error.message}');
          } else {
            // Consent has been gathered (or was not required)
            print('Consent flow completed successfully');
          }
        });
      } else {
        // Consent form not required (user outside EEA/UK/Switzerland)
        print('Consent form not required');
      }
    },
        (FormError error) {
      // Handle errors in consent info update
      print("Consent info update failed: ${error.message}");
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // GDPR COMPLIANCE: Method to show privacy options (consent revocation)
  static Future<void> showPrivacyOptionsForm(BuildContext context) async {
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          print("Error showing privacy options: ${error.message}");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error managing preferences: ${error.message}')),
          );
        } else {
          // Privacy options form completed
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Privacy preferences updated')),
          );
        }
      });
    } catch (e) {
      print("Error opening privacy options: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening privacy options')),
      );
    }
  }

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

      // Supabase query
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
          // GDPR COMPLIANCE: Consent revocation button for testing
          IconButton(
            icon: const Icon(Icons.privacy_tip),
            onPressed: () => MyApp.showPrivacyOptionsForm(context),
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
              // GDPR COMPLIANCE: Consent revocation button
              ElevatedButton.icon(
                onPressed: () => MyApp.showPrivacyOptionsForm(context),
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
"