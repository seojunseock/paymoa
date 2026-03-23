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
        _summary(),
        _section('제1조 (개인정보의 수집 항목 및 수집 방법)', [
          _sub('1) 수집 항목'),
          _body('(1) 소셜 로그인 시 자동 제공되는 정보\n'
              '    • 이메일 주소, 서비스 식별자(UID)\n'
              '    • 카카오 로그인의 경우: 닉네임, 프로필 사진 URL'),
          _body('(2) 이용자가 서비스 이용 과정에서 직접 입력하는 정보\n'
              '    • 알바생: 근무 일정, 근무 시간, 시급\n'
              '    • 사장님: 매장명, 초대코드, 직원 정보(성명, 시급), 근무 스케줄'),
          _body('(3) 서비스 이용 과정에서 자동 생성·수집되는 정보\n'
              '    • 해당 없음 (Firebase Analytics, Firebase Crashlytics 미사용)'),
          _sub('2) 수집하지 않는 정보'),
          _body('• 주민등록번호 · 운전면허번호 등 고유식별정보\n'
              '• 계좌번호 · 카드번호 등 금융정보\n'
              '• 위치정보'),
          _sub('3) 수집 방법'),
          _body('소셜 로그인 SDK(Firebase Authentication, Kakao SDK)를 통한 자동 수집,\n'
              '이용자의 앱 내 직접 입력'),
        ]),
        _section('제2조 (개인정보의 수집·이용 목적)', [
          _body('페이모아는 다음 목적을 위해 개인정보를 처리합니다.\n\n'
              '• 회원 가입 및 본인 식별·인증\n'
              '• 급여 계산, 근무 일정 관리 등 서비스 핵심 기능 제공\n'
              '• 매장-알바생 연결 서비스 제공\n'
              '• 고객 문의 접수 및 처리\n'
              '• 서비스 오류 수정 및 품질 개선'),
        ]),
        _section('제3조 (개인정보의 보유 및 이용 기간)', [
          _body('원칙적으로 이용자가 회원 탈퇴를 요청하거나 개인정보의 수집·이용 목적이 달성된 경우, '
              '지체 없이 해당 개인정보를 파기합니다.\n\n'
              '다만, 관계 법령에 의해 보관이 필요한 경우 해당 기간 동안 별도 보관됩니다.\n\n'
              '• 소비자 불만 또는 분쟁 처리 기록: 3년 (전자상거래 등에서의 소비자보호에 관한 법률)\n\n'
              '• 접속기록(로그): 접속로그를 별도로 수집·저장하지 않습니다. 다만 Firebase 인프라에서 '
              '기술적으로 생성되는 접속 기록은 Google LLC의 정책에 따라 보관될 수 있습니다.'),
        ]),
        _section('제4조 (개인정보의 제3자 제공)', [
          _body('페이모아는 원칙적으로 이용자의 개인정보를 제3자에게 제공하지 않습니다.\n\n'
              '다만, 아래의 경우에는 예외로 합니다.\n'
              '• 이용자가 사전에 동의한 경우\n'
              '• 법령의 규정에 의거하거나, 수사 목적으로 법령에 정해진 절차와 방법에 따라 '
              '수사기관의 요구가 있는 경우'),
        ]),
        _section('제5조 (개인정보 처리의 위탁)', [
          _body('페이모아는 서비스 제공을 위하여 아래와 같이 개인정보 처리 업무를 위탁하고 있습니다.'),
          const SizedBox(height: 8),
          _table([
            ['수탁사', '위탁업무', '처리 위치'],
            ['Google LLC\n(Firebase)', '회원 인증\n(Firebase Authentication),\n데이터 저장\n(Cloud Firestore)', '서울(한국)\nasa-northeast3\n※ Authentication은\n글로벌 인프라 경유 가능'],
            ['Kakao Corp.', '소셜 로그인 처리', '대한민국'],
          ]),
          const SizedBox(height: 8),
          _body('각 수탁사의 개인정보처리방침은 해당 회사 홈페이지에서 확인하실 수 있습니다.'),
        ]),
        _section('제6조 (이용자의 권리·의무 및 행사 방법)', [
          _body('이용자는 언제든지 다음과 같은 권리를 행사할 수 있습니다.\n\n'
              '• 개인정보 열람 요구\n'
              '• 개인정보 오류 정정 요구\n'
              '• 개인정보 삭제 요구\n'
              '• 개인정보 처리정지 요구\n\n'
              '권리 행사는 아래 방법으로 할 수 있습니다.\n'
              '• 앱 내 [내 정보 → 계정 삭제] 기능을 통해 직접 삭제\n'
              '• 이메일 접수: paymoa8@gmail.com\n\n'
              '페이모아는 요청을 받은 날로부터 10일 이내에 처리 결과를 안내합니다.'),
        ]),
        _section('제7조 (개인정보의 파기 절차 및 방법)', [
          _body('페이모아는 개인정보 보유기간의 경과, 처리목적 달성, 회원 탈퇴 등 '
              '개인정보가 불필요하게 되었을 때에는 지체 없이 해당 개인정보를 파기합니다.\n\n'
              '• 전자적 파일: 재생 불가능한 방법으로 영구 삭제\n\n'
              '회원 탈퇴 요청 시 Firebase Firestore 및 Authentication에 저장된 이용자 데이터는 지체 없이 삭제합니다.\n\n'
              '다만, 관계 법령에 따라 보관이 필요한 정보가 있는 경우 해당 기간 동안 별도 보관 후 파기하며, '
              '기술적 특성상 백업 등에서 완전 삭제까지 일정 시간이 소요될 수 있습니다.'),
        ]),
        _section('제8조 (개인정보 자동 수집 장치의 설치·운영 및 거부)', [
          _body('페이모아는 현재 서비스 운영을 위해 쿠키, 광고 식별자 등 개인정보를 자동으로 수집하는 장치를 사용하지 않으며, '
              'Firebase Analytics 및 Firebase Crashlytics 또한 사용하지 않습니다.\n\n'
              '다만, 향후 서비스 기능 추가 또는 운영 방식 변경으로 자동 수집 항목이 발생하는 경우, '
              '관련 법령에 따라 사전에 안내하고 필요한 절차를 거쳐 운영합니다.'),
        ]),
        _section('제9조 (개인정보 보호책임자 및 사업자 정보)', [
          _sub('9-1. 사업자 정보'),
          _body('• 상호: 페이모아 (PAYMOA)\n'
              '• 대표자: 서준석\n'
              '• 사업자등록번호: 449-24-02382\n'
              '• 과세유형: 일반과세자\n'
              '• 업태: 정보통신업\n'
              '• 종목: 응용 소프트웨어 개발 및 공급업\n'
              '• 주소: 광주광역시 서구\n'
              '• 고객 문의 이메일: paymoa8@gmail.com\n'
              '• 전화: (이메일로 대체)'),
          _sub('9-2. 개인정보 보호책임자'),
          _body('• 개인정보 보호책임자: 페이모아 개발팀\n'
              '• 이메일: paymoa8@gmail.com\n\n'
              '개인정보 침해에 관한 신고·상담은 아래 기관에도 문의하실 수 있습니다.\n'
              '• 개인정보침해 신고센터: privacy.kisa.or.kr / ☎ 118\n'
              '• 개인정보 분쟁조정위원회: www.kopico.go.kr / ☎ 1833-6972'),
        ]),
        _section('제10조 (개인정보의 국외 이전)', [
          _sub('10-1. Firestore(서비스 데이터 저장) 처리 위치'),
          _body('• Firestore Data location: 한국(서울, asia-northeast3)\n'
              '• 따라서, 근무 스케줄 등 서비스 운영 데이터(Firestore 저장 데이터)는 '
              '원칙적으로 국외 이전에 해당하지 않습니다.'),
          _sub('10-2. Firebase Authentication(로그인) 관련 처리'),
          _body('Firebase Authentication은 서비스 제공 과정에서 Google의 글로벌 인프라(미국 포함)를 경유하여 '
              '데이터가 처리될 수 있습니다.\n\n'
              '• 이전받는 자(수탁자): Google LLC (Firebase)\n'
              '• 이전되는 국가: 글로벌 인프라 사용(미국 포함)\n'
              '• 이전 시점 및 방법: 서비스 이용 시 네트워크를 통한 전송\n'
              '• 이전 목적: 회원 가입, 로그인, 본인 식별·인증\n'
              '• 이전 항목(예시): 이메일 주소, 서비스 식별자(UID) 등 인증 처리에 필요한 정보\n'
              '• 보유 및 이용 기간: 본 방침의 보유 및 이용 기간에 따르며, 관련 법령 및 수탁사 정책에 따라 처리\n\n'
              'Firebase의 개인정보 처리 관련 안내: firebase.google.com/support/privacy'),
        ]),
        _section('제11조 (개인정보처리방침의 변경)', [
          _body('이 개인정보처리방침은 법령, 정책 또는 보안 기술의 변경에 따라 내용이 변경될 수 있습니다. '
              '변경 시 앱 공지 또는 이메일을 통해 최소 7일 전에 안내합니다.'),
        ]),
        _effectiveDate(),
      ],
    );
  }

  Widget _intro() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '페이모아(이하 "서비스")는 개인정보보호법 등 관련 법령을 준수하며, '
        '이용자의 개인정보를 보호하기 위해 다음과 같이 개인정보처리방침을 수립·공개합니다.',
        style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.65),
      ),
    );
  }

  Widget _summary() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '주요 개인정보 처리 요약',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xFF166534),
            ),
          ),
          SizedBox(height: 8),
          Text(
            '• 처리 항목: 이메일, UID, 닉네임(카카오), 근무 일정·시간·시급, 매장명, 직원 정보\n'
            '• 처리 목적: 회원 인증, 급여 계산, 근무 일정 관리, 매장-알바생 연결\n'
            '• 보유 기간: 회원 탈퇴 또는 목적 달성 시 파기\n'
            '• 국외 이전: Firestore는 서울(한국) 저장. Firebase Auth는 Google 글로벌 인프라 경유 가능\n'
            '• 문의: paymoa8@gmail.com',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF166534),
              height: 1.7,
            ),
          ),
        ],
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
