import 'package:json_annotation/json_annotation.dart';

part 'daily_calendar_response_model.g.dart';

/// Spring/Jackson 등에서 `code`가 숫자로 올 수 있음.
String dailyCalendarApiString(dynamic value) => value?.toString() ?? '';

/// `id`가 문자열·실수로 오거나 null인 경우(일부 자동 일정/공과금 행) 대비.
int dailyCalendarApiInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final v = value.trim();
    if (v.isEmpty) return defaultValue;
    return int.tryParse(v) ?? defaultValue;
  }
  return defaultValue;
}

/// 일정 항목은 `isCompleted`가 null/false인 경우가 있어 null 안전 처리.
bool dailyCalendarApiBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'yes';
  }
  return false;
}

@JsonSerializable()
class DailyCalendarResponseModel {
  final bool isSuccess;
  @JsonKey(fromJson: dailyCalendarApiString)
  final String code;
  final String message;
  final List<DailyCalendarItem>? result;
  final String? error;

  DailyCalendarResponseModel({
    required this.isSuccess,
    required this.code,
    required this.message,
    this.result,
    this.error,
  });

  factory DailyCalendarResponseModel.fromJson(Map<String, dynamic> json) =>
      _$DailyCalendarResponseModelFromJson(json);

  Map<String, dynamic> toJson() => _$DailyCalendarResponseModelToJson(this);
}

@JsonSerializable(createFactory: false)
class DailyCalendarItem {
  @JsonKey(fromJson: dailyCalendarApiString)
  final String category;
  final int id;
  @JsonKey(fromJson: dailyCalendarApiString)
  final String title;
  final String? assigneeName;
  final int? assigneeId;
  final String? choreType;
  @JsonKey(fromJson: dailyCalendarApiBool)
  final bool isCompleted;
  final bool? isOwner;

  DailyCalendarItem({
    required this.category,
    required this.id,
    required this.title,
    this.assigneeName,
    this.assigneeId,
    this.choreType,
    required this.isCompleted,
    this.isOwner,
  });

  /// 백엔드·버전 차이 (`content`/`name`, `assignee`) 흡수 — 파싱 실패로 목록 전체가 비는 것을 방지.
  factory DailyCalendarItem.fromJson(Map<String, dynamic> json) {
    final categoryRaw = dailyCalendarApiString(json['category']);
    final titleRaw = dailyCalendarApiString(
      json['title'] ??
          json['content'] ??
          json['name'] ??
          json['label'] ??
          json['scheduleContent'],
    );
    final assigneeRaw = json['assigneeName'] as String? ??
        json['assignee'] as String?;
    dynamic idRaw = json['id'] ?? json['choreId'];
    int idVal = dailyCalendarApiInt(idRaw);
    final assigneeIdRaw = json['assigneeId'];
    final assigneeIdParsed = assigneeIdRaw == null
        ? null
        : dailyCalendarApiInt(assigneeIdRaw, defaultValue: -1);
    final assigneeId =
        assigneeIdParsed != null && assigneeIdParsed > 0 ? assigneeIdParsed : null;
    final choreTypeRaw = json['choreType'] as String?;
    final choreType = choreTypeRaw?.trim().isNotEmpty == true
        ? choreTypeRaw!.trim()
        : null;
    if (idVal == 0 &&
        idRaw == null &&
        (titleRaw.isNotEmpty || categoryRaw.isNotEmpty)) {
      idVal = -(Object.hash(categoryRaw, titleRaw, assigneeRaw).abs() %
          2147483647);
      if (idVal == 0) idVal = -1;
    }

    return DailyCalendarItem(
      category: categoryRaw,
      id: idVal,
      title: titleRaw,
      assigneeName: assigneeRaw,
      assigneeId: assigneeId,
      choreType: choreType,
      isCompleted: dailyCalendarApiBool(json['isCompleted']),
      isOwner: json['isOwner'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => _$DailyCalendarItemToJson(this);
}















