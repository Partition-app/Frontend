import 'package:json_annotation/json_annotation.dart';

part 'chore_api_models.g.dart';

/// Spring/Jackson 등에서 `code`가 숫자로 올 수 있음.
String choreApiString(dynamic value) => value?.toString() ?? '';

int choreApiInt(dynamic value, {int defaultValue = 0}) {
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

bool choreApiBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'yes';
  }
  return false;
}

/// POST 수동 등록 / PATCH 수정 공통 래퍼 (`result` 단일 객체).
@JsonSerializable()
class ChoreMutationResponseModel {
  final bool isSuccess;
  @JsonKey(fromJson: choreApiString)
  final String code;
  final String message;
  final ChoreApiDetail? result;
  final String? error;

  ChoreMutationResponseModel({
    required this.isSuccess,
    required this.code,
    required this.message,
    this.result,
    this.error,
  });

  factory ChoreMutationResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ChoreMutationResponseModelFromJson(json);

  Map<String, dynamic> toJson() => _$ChoreMutationResponseModelToJson(this);
}

@JsonSerializable()
class ChoreApiDetail {
  @JsonKey(fromJson: choreApiInt)
  final int choreId;
  @JsonKey(fromJson: choreApiInt)
  final int assigneeId;
  final String assigneeName;
  final String choreType;
  final String choreName;
  final String date;
  @JsonKey(fromJson: choreApiBool)
  final bool isCompleted;

  ChoreApiDetail({
    required this.choreId,
    required this.assigneeId,
    required this.assigneeName,
    required this.choreType,
    required this.choreName,
    required this.date,
    required this.isCompleted,
  });

  factory ChoreApiDetail.fromJson(Map<String, dynamic> json) =>
      _$ChoreApiDetailFromJson(json);

  Map<String, dynamic> toJson() => _$ChoreApiDetailToJson(this);
}

/// GET `/chores/daily` 목록 래퍼.
@JsonSerializable()
class ChoreDailyListResponseModel {
  final bool isSuccess;
  @JsonKey(fromJson: choreApiString)
  final String code;
  final String message;
  final List<ChoreDailyApiItem>? result;
  final String? error;

  ChoreDailyListResponseModel({
    required this.isSuccess,
    required this.code,
    required this.message,
    this.result,
    this.error,
  });

  factory ChoreDailyListResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ChoreDailyListResponseModelFromJson(json);

  Map<String, dynamic> toJson() => _$ChoreDailyListResponseModelToJson(this);
}

@JsonSerializable()
class ChoreDailyApiItem {
  @JsonKey(fromJson: choreApiInt)
  final int choreId;
  @JsonKey(fromJson: choreApiInt)
  final int assigneeId;
  final String assigneeName;
  final String? assigneeProfileImage;
  final String choreType;
  final String choreName;
  final String date;
  @JsonKey(fromJson: choreApiBool)
  final bool isCompleted;

  ChoreDailyApiItem({
    required this.choreId,
    required this.assigneeId,
    required this.assigneeName,
    this.assigneeProfileImage,
    required this.choreType,
    required this.choreName,
    required this.date,
    required this.isCompleted,
  });

  factory ChoreDailyApiItem.fromJson(Map<String, dynamic> json) =>
      _$ChoreDailyApiItemFromJson(json);

  Map<String, dynamic> toJson() => _$ChoreDailyApiItemToJson(this);
}
