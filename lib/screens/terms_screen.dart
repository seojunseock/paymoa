// lib/screens/terms_screen.dart
import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

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
          '서비스 이용약관',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: _TermsContent(),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(),
        _section('제1조 (목적)', [
          _body('본 약관은 페이모아(PAYMOA)(이하 "회사")가 제공하는 앱 기반 서비스(이하 "서비스")의 이용과 관련하여 '
              '회사와 이용자 간의 권리, 의무 및 책임사항과 기타 필요한 사항을 규정함을 목적으로 합니다.'),
        ]),
        _section('제2조 (회사 정보)', [
          _body('• 상호: 페이모아 (PAYMOA)\n'
              '• 대표자: 서준석\n'
              '• 사업자등록번호: 449-24-02382\n'
              '• 과세유형: 일반과세자\n'
              '• 업태: 정보통신업\n'
              '• 종목: 응용 소프트웨어 개발 및 공급업\n'
              '• 주소: 광주광역시 서구\n'
              '• 고객 문의 이메일: paymoa8@gmail.com\n'
              '• 전화: (이메일로 대체)\n\n'
              '※ 보다 상세한 주소 및 연락처는 확정되는 대로 서비스 내 또는 별도 고지로 안내합니다.'),
        ]),
        _section('제3조 (약관의 효력 및 변경)', [
          _body('1. 본 약관은 이용자가 서비스 가입 또는 이용 과정에서 본 약관에 동의함으로써 효력이 발생합니다.\n\n'
              '2. 회사는 관련 법령을 위반하지 않는 범위에서 약관을 변경할 수 있습니다.\n\n'
              '3. 약관이 변경되는 경우, 회사는 변경 내용과 적용일자를 서비스 내 공지 등 합리적인 방법으로 사전에 안내합니다.'),
        ]),
        _section('제4조 (이용계약의 성립)', [
          _body('1. 이용계약은 이용자가 앱 내 동의 화면에서 본 약관 및 관련 고지사항에 동의하고, '
              '회사가 가입 신청을 승인함으로써 성립합니다.\n\n'
              '2. 회사는 다음 각 호에 해당하는 경우 가입 신청을 거절하거나 사후에 이용계약을 해지할 수 있습니다.\n'
              '   • 타인의 정보를 도용하거나 허위 정보를 기재한 경우\n'
              '   • 기타 회사가 정한 가입 요건을 충족하지 못한 경우'),
        ]),
        _section('제5조 (서비스의 내용)', [
          _body('회사가 제공하는 서비스의 주요 내용은 다음과 같습니다.\n\n'
              '• 근무 기록 관리(근무 일정 및 근무 시간 등)\n'
              '• 급여 계산(예: 시급 및 근무시간 기반 계산)\n'
              '• 서비스 이용을 위한 문서의 생성 및 제공(예: 근무/급여 관련 출력물 또는 내보내기 기능 등)\n\n'
              '※ 본 서비스는 현재 무료로 제공되며, 회사는 향후 구독 등 유료 서비스를 도입할 수 있습니다. '
              '유료 서비스 도입 시 결제, 청약철회, 환불 등 세부 조건은 관련 법령에 따라 서비스 내 또는 별도 공지로 안내합니다.\n\n'
              '※ 서비스의 구체적인 기능 및 제공 범위는 회사의 운영 정책 및 서비스 화면에 따릅니다.'),
        ]),
        _section('제6조 (이용자의 의무)', [
          _body('이용자는 서비스를 이용함에 있어 다음 각 호의 행위를 하여서는 안 됩니다.\n\n'
              '• 허위 정보를 등록하거나 타인의 정보를 무단으로 사용·도용하는 행위\n'
              '• 회사 또는 제3자의 권리(지식재산권, 개인정보 등)를 침해하는 행위\n'
              '• 서비스의 정상적인 운영을 방해하는 행위(비정상적 접근, 과도한 트래픽 유발 등)\n'
              '• 관련 법령 및 본 약관, 운영정책을 위반하는 행위'),
        ]),
        _section('제6-1조 (계정 제한 및 이용계약 해지)', [
          _body('1. 회사는 이용자가 다음 각 호에 해당하는 경우, 사전 통지 후 또는 긴급한 경우 '
              '사후 통지로 서비스 이용을 제한(일시 정지)하거나 이용계약을 해지할 수 있습니다.\n'
              '   • 허위정보 등록 또는 타인 정보 무단 사용\n'
              '   • 서비스 악용 또는 보안상 위험을 초래하는 행위\n'
              '   • 기타 본 약관 또는 관련 법령 위반\n\n'
              '2. 이용자는 앱 내 기능을 통해 언제든지 회원 탈퇴를 할 수 있습니다.'),
        ]),
        _section('제7조 (서비스의 제공, 변경 및 중단)', [
          _body('1. 회사는 서비스를 연중무휴 제공함을 원칙으로 하나, 시스템 점검, 장애, '
              '통신망 불안정, 천재지변 등 불가피한 사유가 있는 경우 서비스의 전부 또는 일부를 일시적으로 중단할 수 있습니다.\n\n'
              '2. 회사는 서비스의 일부 또는 전부를 변경할 수 있으며, '
              '이용자에게 불리한 변경이 있는 경우 합리적인 방법으로 사전에 안내합니다.'),
        ]),
        _section('제8조 (책임의 제한)', [
          _body('1. 회사가 제공하는 급여 계산 결과, 근무 관련 산출물 및 기타 계산값은 참고용이며, '
              '법적 효력을 갖는 확정 자료가 아닙니다.\n\n'
              '2. 회사는 이용자가 입력한 정보의 정확성에 대해 보증하지 않으며, '
              '이용자가 입력한 정보의 오류 또는 누락으로 발생한 손해에 대하여 '
              '회사의 고의 또는 중대한 과실이 없는 한 책임을 지지 않습니다.\n\n'
              '3. 회사는 관련 법령상 허용되는 범위 내에서 간접손해, 특별손해, 결과적 손해 등에 대하여 책임을 제한할 수 있습니다.'),
        ]),
        _section('제9조 (분쟁 해결 및 준거법)', [
          _body('1. 본 약관과 서비스 이용에 관한 분쟁은 대한민국 법령을 준거법으로 합니다.\n\n'
              '2. 회사와 이용자 간 분쟁이 발생한 경우, 상호 성실히 협의하여 해결하도록 노력합니다.'),
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
        '페이모아 서비스를 이용하시기 전에 이 이용약관을 꼭 읽어보세요. '
        '소셜 로그인 후 나타나는 약관 동의 화면에서 직접 동의를 완료해야 서비스를 이용할 수 있습니다.',
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
            padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
            '부칙',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151)),
          ),
          SizedBox(height: 4),
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
