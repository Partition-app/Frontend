/// 집안일 배정 모달(AI·직접) 공통 상수·변환
const List<String> kChoreDisplayNames = [
  '설거지',
  '요리',
  '빨래',
  '음식물 쓰레기 버리기',
  '분리수거',
  '청소기 돌리기',
  '바닥 닦기',
  '창문, 창틀 닦기',
  '화장실 청소',
  '냉장고 청소',
];

const Map<String, String> kChoreNameToEnum = {
  '설거지': 'DISH_WASHING',
  '요리': 'COOKING',
  '빨래': 'LAUNDRY',
  '음식물 쓰레기 버리기': 'FOODTRASH',
  '분리수거': 'RECYCLING',
  '청소기 돌리기': 'VACUUM',
  '바닥 닦기': 'MOPPING',
  '창문, 창틀 닦기': 'WINDOW',
  '화장실 청소': 'BATHROOM',
  '냉장고 청소': 'FRIDGE',
};

const Map<String, String> kChoreEnumToName = {
  'DISH_WASHING': '설거지',
  'COOKING': '요리',
  'LAUNDRY': '빨래',
  'FOODTRASH': '음식물 쓰레기 버리기',
  'RECYCLING': '분리수거',
  'VACUUM': '청소기 돌리기',
  'MOPPING': '바닥 닦기',
  'WINDOW': '창문, 창틀 닦기',
  'BATHROOM': '화장실 청소',
  'FRIDGE': '냉장고 청소',
};

List<String> choreDisplayNamesToEnum(List<String> names) =>
    names.map((n) => kChoreNameToEnum[n] ?? n).toList();

String choreEnumToDisplayName(String enumValue) =>
    kChoreEnumToName[enumValue] ?? enumValue;

String formatChoreDateForApi(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime choreDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

bool choreIsSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
