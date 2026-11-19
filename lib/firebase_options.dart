import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDyPd_vzWrvkxDMvWiwv8r3b-vqRaImrNM',
    appId: '1:915997041578:web:f672b65c44fa33df4f81d3',
    messagingSenderId: '915997041578',
    projectId: 'pulsegaurd-sos',
    authDomain: 'pulsegaurd-sos.firebaseapp.com',
    storageBucket: 'pulsegaurd-sos.firebasestorage.app',
  );

  // जब Android app के लिए अलग Firebase Android app रजिस्टर करें,
  // तो यहाँ Android का appId अपडेट किया जा सकता है।
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDyPd_vzWrvkxDMvWiwv8r3b-vqRaImrNM',
    appId: '1:915997041578:web:f672b65c44fa33df4f81d3',
    messagingSenderId: '915997041578',
    projectId: 'pulsegaurd-sos',
    authDomain: 'pulsegaurd-sos.firebaseapp.com',
    storageBucket: 'pulsegaurd-sos.firebasestorage.app',
  );
}
