// lib/screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '개인정보처리방침',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: _PolicyContent(),
      ),
    );
  }
}

class _PolicyContent extends StatelessWidget {
  const _PolicyContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(),
        _section('제1조 (수집하는 개인정보 항목 및 수집 방법)', [
          _sub('수집 항목'),
          _body('① 소셜 로그인(이메일·카카오) 시 자동 제공되는 정보\n'
              '    • 이메일 주소, 서비스 식별자(UID)\n'
              '    • 카카오 로그인의 경우: 닉네임, 프로필 사진 URL'),
          _body('② 이용자가 서비스 이용 과정에서 직접 입력하는 정보\n'
              '    • 알바생: 근무 일정, 근무 시간, 시급\n'
              '    • 사장님: 매장명, 초대코드, 알바생 정보(성명, 시급), 근무 스케줄'),
          _body('③ 서비스 이용 과정에서 자동 생성·수집되는 정보\n'
              '    • 앱 사용 통계(Firebase Analytics — 비식별 처리)\n'
              '    • 오류 로그(Firebase Crashlytics — 비식별 처리)'),
          _sub('수집하지 않는 정보'),
          _body('• 주민등록번호 · 운전면허번호 등 고유식별정보\n'
              '• 계좌번호 · 카드번호 등 금융정보\n'
              '• 위치정보'),
          _sub('수집 방법'),
          _body('소셜 로그인 SDK(Firebase Authentication, Kakao SDK)를 통한 자동 수집,\n'
              '이용자의 앱 내 직접 입력'),
        ]),
        _section('제2조 (개인정보의 수집 및 이용 목적)', [
          _body('• 회원 가입 및 본인 식별·인증\n'
              '• 급여 계산, 근무 일정 관리 등 서비스 핵심 기능 제공\n'
              '• 매장-알바생 연결 서비스 제공\n'
              '• 고객 문의 접수 및 처리\n'
              '• 서비스 오류 수정 및 품질 개선'),
        ]),
        _section('제3조 (개인정보의 보유 및 이용 기간)', [
          _body('이용자가 회원 탈퇴를 요청하거나 개인정보의 수집·이용 목적이 달성된 경우 '
              '지체 없이 파기합니다.\n\n'
              '단, 관계 법령에 의해 보관이 필요한 경우 해당 기간 동안 별도 보관됩니다.\n\n'
              '• 소비자 불만 또는 분쟁 처리 기록: 3년 (전자상거래법)\n'
              '• 서비스 이용 기록·접속 로그: 3개월 (통신비밀보호법)'),
        ]),
        _section('제4조 (개인정보의 제3자 제공)', [
          _body('페이모아는 원칙적으로 이용자의 개인정보를 제3자에게 제공하지 않습니다.\n\n'
              '다만, 아래의 경우에는 예외로 합니다.\n'
              '• 이용자가 사전에 동의한 경우\n'
              '• 법령의 규정에 의거하거나, 수사 목적으로 법령에 정해진 절차와 방법에 따라\n'
              '  수사기관의 요구가 있는 경우'),
        ]),
        _section('제5조 (개인정보 처리 위탁)', [
          _body('서비스 제공을 위해 아래와 같이 개인정보 처리 업무를 위탁하고 있습니다.'),
          const SizedBox(height: 8),
          _table([
            ['수탁사', '위탁 업무', '국가'],
            ['Google LLC\n(Firebase)', '클라우드 데이터 저장,\n회원 인증', '미국'],
            ['Kakao Corp.', '소셜 로그인 처리', '대한민국'],
          ]),
          const SizedBox(height: 8),
          _body('각 수탁사의 개인정보처리방침은 해당 회사 홈페이지에서 확인하실 수 있습니다.'),
        ]),
        _section('제6조 (이용자의 권리·의무 및 행사 방법)', [
          _body('이용자는 언제든지 다음과 같은 권리를 행사할 수 있습니다.\n\n'
              '① 개인정보 열람 요구\n'
              '② 개인정보 오류 정정 요구\n'
              '③ 개인정보 삭제 요구\n'
              '④ 개인정보 처리정지 요구\n\n'
              '권리 행사는 앱 내 [내 정보 → 계정 삭제] 기능을 통해 직접 삭제하거나,\n'
              'paymoa8@gmail.com으로 이메일을 보내 요청하실 수 있습니다.\n\n'
              '요청을 받은 날로부터 10일 이내에 처리 결과를 알려드립니다.'),
        ]),
        _section('제7조 (개인정보의 파기 절차 및 방법)', [
          _body('• 전자적 파일: 재생 불가능한 방법으로 영구 삭제\n'
              '• 종이 문서(해당 시): 분쇄기 파쇄 또는 소각\n\n'
              '회원 탈퇴 요청 시 Firebase Firestore 및 Authentication에 저장된\n'
              '모든 이용자 데이터를 즉시 삭제합니다.'),
        ]),
        _section('제8조 (개인정보 자동 수집 장치의 설치·운영 및 거부)', [
          _body('서비스는 Firebase Analytics, Firebase Crashlytics를 통해\n'
              '앱 사용 패턴 및 오류 정보를 수집합니다. 이 데이터는 비식별 처리되어\n'
              '개인을 특정하는 데 사용되지 않습니다.\n\n'
              '기기 설정에서 앱 추적 거부(iOS) 또는 광고 ID 재설정(Android)을 통해\n'
              '일부 자동 수집을 제한할 수 있습니다.'),
        ]),
        _section('제9조 (개인정보 보호책임자)', [
          _body('서비스의 개인정보 처리에 관한 업무를 총괄하고,\n'
              '관련 고충 처리를 담당하는 책임자는 다음과 같습니다.\n\n'
              '• 개인정보 보호책임자: 페이모아 개발팀\n'
              '• 이메일: paymoa8@gmail.com\n\n'
              '개인정보 침해에 관한 신고·상담은 아래 기관에도 문의하실 수 있습니다.\n'
              '• 개인정보침해 신고센터: privacy.kisa.or.kr / ☎ 118\n'
              '• 개인정보 분쟁조정위원회: www.kopico.go.kr / ☎ 1833-6972'),
        ]),
        _section('제10조 (국외 이전)', [
          _body('서비스는 Google LLC(미국)의 Firebase 서버를 이용합니다.\n'
              'Firebase의 개인정보 처리 방침은 다음에서 확인하실 수 있습니다.\n'
              '• https://firebase.google.com/support/privacy'),
        ]),
        _section('제11조 (개인정보처리방침의 변경)', [
          _body('이 개인정보처리방침은 법령, 정책 또는 보안 기술의 변경에 따라 '
              '내용이 변경될 수 있습니다. 변경 시 앱 공지 또는 이메일을 통해 최소 7일 전에 안내합니다.'),
        ]),
        _effectiveDate(),
      ],
    );
  }

  Widget _intro() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '페이모아(이하 "서비스")는 개인정보보호법, 정보통신망 이용촉진 및 정보보호 등에 관한 법률 등 관련 법령을 준수하며, '
        '이용자의 개인정보를 보호하기 위해 다음과 같이 개인정보처리방침을 수립·공개합니다.',
        style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.65),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Color(0xFF5B21B6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _sub(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Widget _body(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF374151),
          height: 1.65,
        ),
      ),
    );
  }

  Widget _table(List<List<String>> rows) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          final isHeader = i == 0;
          return Container(
            decoration: BoxDecoration(
              color: isHeader
                  ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: i == 0
                  ? const BorderRadius.vertical(top: Radius.circular(7))
                  : i == rows.length - 1
                      ? const BorderRadius.vertical(bottom: Radius.circular(7))
                      : null,
              border: i > 0
                  ? const Border(top: BorderSide(color: Color(0xFFE5E7EB)))
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                children: row.asMap().entries.map((cell) {
                  final j = cell.key;
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: j > 0
                          ? const BoxDecoration(
                              border: Border(
                                  left: BorderSide(color: Color(0xFFE5E7EB))))
                          : null,
                      child: Text(
                        cell.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isHeader ? FontWeight.w700 : FontWeight.w400,
                          color: isHeader
                              ? const Color(0xFF5B21B6)
                              : const Color(0xFF374151),
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _effectiveDate() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '공고일: 2026년 3월 1일',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280)),
          ),
          SizedBox(height: 2),
          Text(
            '시행일: 2026년 3월 1일',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
