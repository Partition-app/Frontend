import 'package:json_annotation/json_annotation.dart';

part 'household_response_model.g.dart';

@JsonSerializable()
class HouseholdResponseModel {
  final bool isSuccess;
  final String code;
  final String message;
  final HouseholdResult? result;
  final String? error;

  HouseholdResponseModel({
    required this.isSuccess,
    required this.code,
    required this.message,
    this.result,
    this.error,
  });

  factory HouseholdResponseModel.fromJson(Map<String, dynamic> json) {
    return HouseholdResponseModel(
      isSuccess: json['isSuccess'] == true,
      code: (json['code'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      result: json['result'] is Map<String, dynamic>
          ? HouseholdResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => _$HouseholdResponseModelToJson(this);
}

@JsonSerializable()
class HouseholdResult {
  /// 초대 코드. 서버는 `inviteCode` 또는 레거시 `code`로 줄 수 있음.
  final String? code;
  final String? name; // 그룹명
  final int? id; // 그룹 ID
  final String? role; // 사용자 역할 (LEADER 등)

  HouseholdResult({
    this.code,
    this.name,
    this.id,
    this.role,
  });

  factory HouseholdResult.fromJson(Map<String, dynamic> json) {
    final rawIsLeader = json['isLeader'];
    final bool? isLeader = rawIsLeader is bool
        ? rawIsLeader
        : (rawIsLeader is String
              ? rawIsLeader.toLowerCase() == 'true'
              : null);

    String? readString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return null;
    }

    int? readInt(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        if (value is int) return value;
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value.toString().trim());
        if (parsed != null) return parsed;
      }
      return null;
    }

    final parsedRole = readString(['role']) ??
        (isLeader == null ? null : (isLeader ? 'LEADER' : 'MEMBER'));

    return HouseholdResult(
      // GET /households/me: inviteCode · 레거시: code / householdCode
      code: readString(['inviteCode', 'code', 'householdCode']),
      name: readString(['name', 'householdName']),
      id: readInt(['id', 'householdId']),
      role: parsedRole,
    );
  }

  Map<String, dynamic> toJson() => _$HouseholdResultToJson(this);
}

