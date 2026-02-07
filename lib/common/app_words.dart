// lib/common/app_words.dart
/// 앱 전체에서 쓰는 문구/단어 통일용.
/// ✅ 반드시 static const String만 사용 (const Text(...)에서 쓰기 위해)
class AppWords {
  AppWords._();

  // app
  static const String appName = 'PayCount';

  // common
  static const String ok = '확인';
  static const String cancel = '취소';
  static const String close = '닫기';
  static const String select = '선택';
  static const String back = '뒤로';
  static const String next = '다음';
  static const String save = '저장';
  static const String edit = '수정';
  static const String delete = '삭제';
  static const String done = '완료';
  static const String failed = '실패';
  static const String none = '없음';

  // auth / state
  static const String loginRequired = '로그인이 필요해요.';
  static const String saveLinkRequired = '저장 연결이 필요해요.';

  // work / schedule
  static const String noWork = '근무 없음';
  static const String addWork = '근무 추가';
  static const String workTime = '근무시간';
  static const String breakTime = '쉬는시간';
  static const String workDate = '근무날짜';

  // join store
  static const String joinByCode = '매장 코드로 추가';
  static const String addDirect = '직접 추가';
  static const String infoInput = '정보 입력';
  static const String name = '이름';
  static const String nameHint = '예) 홍길동';
  static const String storeAlias = '매장 이름(내가 보기 좋게)';
  static const String storeAliasHint = '예) 강남 카페';
  static const String inheritStoreSetting = '매장 설정 그대로 쓰기';
  static const String on = '켜짐';
  static const String off = '꺼짐';

  // empty view
  static const String emptyTitle = '아직 없어요';
  static const String emptyHelp = '+ 버튼을 눌러 추가하세요.';

  // labels
  static const String tax = '세금';
  static const String insurance = '보험';
  static const String surcharge = '가산';
  static const String payroll = '급여';

  // work type (통일)
  static const String workTypeBasic = '기본';
  static const String workTypeSubstitute = '대타';
  static const String workTypeOvertime = '연장';
  static const String workTypeHoliday = '휴일';
  static const String workTypeNight = '야간';

  // calendar / units
  static const String calendar = '캘린더';
  static const String prevMonth = '이전 달';
  static const String nextMonth = '다음 달';
  static const String monthlyNetEstimate = '이번 달 예상 실수령:';

  static const String hourlyWage = '시급';
  static const String untilToday = '오늘까지';
  static const String workCount = '근무';
  static const String monthUnit = '월';
  static const String dayUnit = '일';
  static const String timesUnit = '회';

  // insurance short labels
  static const String insuranceEmploymentShort = '고용';
  static const String insuranceFourShort = '4대';

  // surcharge label
  static const String weeklyHoliday = '주휴';

  // payroll labels
  static const String payCycleMonthly = '월급';
  static const String payCycleWeekly = '주급';
  static const String payCycleTwoWeeks = '2주';
  static const String payCycleDaily = '일급';
  static const String payRuleMonthlyPrefix = '매월';
  static const String payRuleEndDay = '마감일';
  static const String payRuleEndPlusPrefix = '마감+';
  static const String payRuleFixed = '지정일';

  // -------- MyInfoScreen (추가) --------
  static const String logout = '로그아웃';
  static const String logoutConfirmTitle = '로그아웃 하시겠습니까?';
  static const String logoutDone = '로그아웃 완료';
  static const String logoutFailed = '로그아웃에 실패했어요.';

  static const String refresh = '갱신';
  static const String refreshDone = '갱신 완료';
  static const String refreshNeededTitle = '갱신이 필요해요';
  static const String payDayLabel = '급여일';

  static const String terms = '이용약관';
  static const String privacy = '개인정보 처리방침';
  static const String openSourceLicense = '오픈소스 라이선스';
  static const String faq = 'FAQ';
  static const String support = '문의하기';
  static const String deleteAccount = '회원탈퇴';

  // -------- PayrollPolicySheet (추가) --------
  static const String payrollPolicyTitle = '급여 방식 설정';
  static const String step1 = '1단계';
  static const String step2 = '2단계';
  static const String step3 = '3단계';
  static const String change = '바꾸기'; // ✅ 중복이면 "하나만" 유지해야 함
  static const String doneUpper = '완료'; // 필요하면 구분용 (done과 같아도 되면 삭제 가능)

  static const String policyBundleQuestion = '일한 기간을 어떻게 묶을까요?';
  static const String policyKindCalendarMonth = '한 달(1일~말일)로 묶기';
  static const String policyKindCalendarMonthSub = '가장 많이 쓰는 방식';
  static const String policyKindAnchorMonth =
      '매달 같은 날 기준으로 묶기 (예: 16일~다음달 15일)';
  static const String policyKindAnchorMonthSub = '사장님이 정한 기준일로 묶어요';
  static const String policyKindDaily = '하루씩 따로 계산하기(일급)';
  static const String policyKindDailySub = '근무한 날마다 따로 계산해요';

  static const String policyAnchorPickTitle = '기준 시작일 고르기';
  static const String policyPickMonthlyPayDayTitle = '매달 지급일 고르기';
  static const String policyPayWhenTitle = '돈은 언제 주나요?';
  static const String policyPaySameEnd = '마감하는 날에 바로 지급';
  static const String policyPayAfterDays = '마감하고 며칠 뒤에 지급';
  static const String policyPayMonthlyDay = '마감 후, 매달 N일에 지급';
  static const String policyPickDate = '날짜 바꾸기';

  static const String previewTitle = '예시 확인';
  // role / start
  static const String startTitle = '시작하기';
  static const String rolePickTitle = '어떤 모드로 시작할까요?';
  static const String rolePickHint = '나중에 바꿀 수 있어요.';
  static const String saving = '저장 중…';
  static const String saveFailed = '저장에 실패했어요.';
  static const String owner = '사장님';
  static const String worker = '알바생';

  // owner placeholder
  static const String ownerTitle = '사장님';
  static const String ownerComingSoon = '사장님 화면은 준비 중이에요.';
  // work editor
  static const String workAddTitle = '근무 추가';
  static const String workEditTitle = '근무 수정';

  static const String workPickAlbaTitle = '어떤 알바인가요?';
  static const String workPickAlbaHint = '매장 선택';
  static const String workPickTypeTitle = '어떤 근무인가요?';
  static const String workPolicyOpen = '정책 설정';

  static const String workSettingsTitle = '근무 설정';
  static const String workPickTime = '시간 선택';
  static const String workOpenCalendar = '달력 열기';

  static const String workStart = '시작';
  static const String workEnd = '종료';
  static const String nextDaySuffix = '(다음날)';

  static const String set = '설정';
  static const String reset = '초기화';

  static const String minuteUnit = '분';
  static const String wonUnit = '원';

  static const String workWageOverrideLabel = '이 근무 시급';
  static const String workWageOverrideTitle = '이 근무 시급(선택)';
  static const String workWageOverrideHint = '비우면 기본 시급 사용';
  static const String workWageOverrideDefault = '기본 시급 사용';

  static const String invalidNumber = '올바른 숫자를 입력하세요.';

  static const String workPickAlbaWarn = '알바를 선택하세요.';
  static const String workPickDateWarn = '근무 날짜를 선택하세요.';

  static const String workConflictTitle = '겹치는 알바가 있습니다';
  static const String workConflictBodyPrefix = '';
  static const String workConflictBodySuffix =
      ' 에 같은 시간대의 다른 근무가 있어 저장할 수 없어요.\n시간을 조정한 뒤 다시 시도해 주세요.';

  static const String workDeleteConfirmTitle = '이 근무를 삭제할까요?';
  static const String workDeleteConfirmBody = '삭제 후 되돌릴 수 없습니다.';
  static const String deleteFailed = '삭제에 실패했어요.';
  // owner - invite code
  static const String ownerInviteCodeTitle = '초대 코드';
  static const String ownerStoreLabel = '매장';
  static const String ownerInviteCodeLabel = '초대 코드';
  static const String ownerCodeCopied = '코드가 복사되었습니다.';
  static const String ownerShareTodo = 'TODO: 공유 기능 연결';
  static const String ownerInviteHelp =
      '알바생에게 이 코드를 알려주면,\n알바 앱에서 “코드 입력”으로 바로 매장에 합류할 수 있어요.';

  static const String copy = '복사';
  static const String share = '공유';
}
