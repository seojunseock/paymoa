// lib/auth/auth_service.dart
//
// ✅ 구글  → Firebase 직접 지원. 완전 구현.
// ✅ 애플  → Firebase 직접 지원. 완전 구현. (iOS 필수)
// ✅ 카카오 → 카카오 영구 ID 기반 파생 이메일/비밀번호로 Firebase 연결.
//            서버/Functions 불필요. Spark(무료) 플랜에서 작동.
//            같은 카카오 계정 = 항상 같은 Firebase UID → 데이터 영구 보존.
//
// 카카오 네이티브 앱 키: 0caeaf697a204f827b9d8525bd376311

import 'dart:convert';
import 'dart:math';


import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 카카오 로그인 ✅ 완전 구현 (서버 불필요, Spark 무료 플랜)
  //
  // 카카오 영구 userId → 결정론적 이메일/비밀번호 파생
  // → Firebase Email/Password 계정 생성 or 로그인
  // → 같은 카카오 계정 = 항상 같은 Firebase UID
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<User?> signInWithKakao() async {
    try {
      // 1. 카카오 로그인 (앱 → 실패 시 웹 fallback)
      if (await isKakaoTalkInstalled()) {
        try {
          await UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        await UserApi.instance.loginWithKakaoAccount();
      }

      // 2. 카카오 영구 고유 ID 조회
      final kakaoUser = await UserApi.instance.me();
      final kakaoId = kakaoUser.id.toString();

      // 3. Firebase 파생 이메일/비밀번호 생성
      final email = 'kakao_$kakaoId@kakao.paycount.app';
      final password = _deriveKakaoPassword(kakaoId);

      // 4. Firebase 로그인 시도 → 없으면 계정 생성
      try {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        return cred.user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          try {
            final cred =
                await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
            return cred.user;
          } on FirebaseAuthException catch (e2) {
            if (e2.code == 'email-already-in-use') {
              rethrow;
            }
            rethrow;
          }
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 카카오 userId로부터 결정론적 비밀번호를 파생합니다.
  /// 같은 카카오 계정은 항상 같은 비밀번호를 생성합니다.
  String _deriveKakaoPassword(String kakaoId) {
    const salt = 'paycount_kakao_v1_K9mP2xR7';
    final bytes = utf8.encode('$salt:$kakaoId');
    return sha256.convert(bytes).toString().substring(0, 32);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 구글 로그인 ✅ 완전 구현
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      return cred.user;
    } catch (e) {
      rethrow;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 애플 로그인 ✅ 완전 구현 (iOS App Store 필수)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<User?> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final cred =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      return cred.user;
    } catch (e) {
      rethrow;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 로그아웃
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    try {
      await UserApi.instance.logout();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 애플 로그인 헬퍼 (nonce)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}
