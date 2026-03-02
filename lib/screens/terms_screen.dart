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
          _body('이 약관은 페이모아(이하 "서비스")가 제공하는 급여 계산 및 근무 일정 관리 서비스의 이용 조건과 '
              '절차, 이용자와 서비스 간의 권리·의무 및 책임 사항을 규정함을 목적으로 합니다.'),
        ]),
        _section('제2조 (정의)', [
          _body('① "서비스"란 페이모아 앱을 통해 제공되는 급여 계산, 근무 일정 관리, '
              '매장·알바생 연결 등 모든 기능을 의미합니다.\n\n'
              '② "이용자"란 이 약관에 동의하고 서비스를 이용하는 사람을 말합니다.\n\n'
              '③ "사장님"이란 매장을 등록하고 알바생을 관리하는 이용자를 말합니다.\n\n'
              '④ "알바생"이란 매장에 합류하여 근무 정보를 관리하는 이용자를 말합니다.'),
        ]),
        _section('제3조 (약관의 효력 및 변경)', [
          _body('① 이 약관은 서비스 내에 게시하거나 앱 업데이트를 통해 공지합니다.\n\n'
              '② 서비스는 합리적인 이유가 있을 경우 약관을 변경할 수 있으며, '
              '변경 시 적용일 7일 전에 공지합니다.\n\n'
              '③ 변경된 약관에 동의하지 않으면 서비스 이용을 중단하고 탈퇴할 수 있습니다.'),
        ]),
        _section('제4조 (이용 계약 체결)', [
          _body('① 이용 계약은 이용자가 약관에 동의하고 소셜 로그인을 완료함으로써 성립합니다.\n\n'
              '② 만 14세 미만의 아동은 서비스를 이용할 수 없습니다.\n\n'
              '③ 타인의 명의를 도용하거나 허위 정보를 입력한 경우 가입이 취소될 수 있습니다.'),
        ]),
        _section('제5조 (서비스 이용)', [
          _body('① 서비스는 연중무휴, 24시간 제공을 원칙으로 합니다. 단, 시스템 점검·장애 시 '
              '일시적으로 중단될 수 있습니다.\n\n'
              '② 서비스에서 제공하는 급여 계산 결과는 참고용이며, '
              '실제 지급액은 근로계약 및 관련 법령에 따라 달라질 수 있습니다.\n\n'
              '③ 세금·보험 계산은 입력된 정보를 기반으로 산출되며, '
              '서비스는 계산 결과의 정확성에 대해 법적 책임을 지지 않습니다.'),
        ]),
        _section('제6조 (이용자의 의무)', [
          _body('① 이용자는 다음 행위를 해서는 안 됩니다.\n\n'
              '   • 타인의 개인정보를 무단으로 수집·저장·공개하는 행위\n'
              '   • 서비스의 정상적인 운영을 방해하는 행위\n'
              '   • 서비스를 통해 타인에게 피해를 주는 행위\n'
              '   • 관련 법령 및 이 약관을 위반하는 행위\n\n'
              '② 이용자는 자신의 계정 정보를 타인과 공유하거나 양도할 수 없습니다.'),
        ]),
        _section('제7조 (서비스의 제한 및 중단)', [
          _body('서비스는 다음 각 호의 경우 이용자에 대한 서비스 제공을 제한하거나 중단할 수 있습니다.\n\n'
              '• 이용자가 이 약관을 위반한 경우\n'
              '• 서비스 설비의 보수 및 점검이 필요한 경우\n'
              '• 천재지변, 국가 비상사태 등 불가항력적 사유가 있는 경우'),
        ]),
        _section('제8조 (서비스의 면책)', [
          _body('① 서비스는 이용자가 입력한 데이터의 정확성에 대해 책임지지 않습니다.\n\n'
              '② 서비스는 이용자의 귀책 사유로 인한 데이터 손실에 대해 책임지지 않습니다.\n\n'
              '③ 서비스는 급여 계산 결과로 인한 노사 간 분쟁에 개입하지 않습니다.'),
        ]),
        _section('제9조 (저작권)', [
          _body('서비스가 제공하는 앱, 디자인, 로고, 콘텐츠 등의 저작권은 페이모아 개발팀에 귀속되며, '
              '이용자는 이를 무단으로 복제·배포·변경할 수 없습니다.'),
        ]),
        _section('제10조 (분쟁 해결)', [
          _body('① 이 약관에 관한 분쟁은 대한민국 법령을 적용합니다.\n\n'
              '② 서비스 이용과 관련하여 분쟁이 발생한 경우, '
              'paymoa8@gmail.com으로 문의하여 원만하게 해결할 수 있도록 노력합니다.\n\n'
              '③ 소송이 필요한 경우 관할 법원은 서비스 제공자의 주소지 관할 법원으로 합니다.'),
        ]),
        _section('제11조 (기타)', [
          _body('이 약관에서 정하지 않은 사항은 개인정보보호법, 정보통신망법, 전자상거래법 등 '
              '관련 법령 및 상관례에 따릅니다.'),
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
        '소셜 로그인을 완료하면 아래 약관에 동의한 것으로 간주합니다.',
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
