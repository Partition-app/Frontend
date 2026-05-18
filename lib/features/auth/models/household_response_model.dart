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
class HouseholdMemberModel {
  final int userId;
  final String name;
  final String? profileImage;
  final String? role;

  const HouseholdMemberModel({
    required this.userId,
    required this.name,
    this.profileImage,
    this.role,
  });

  factory HouseholdMemberModel.fromJson(Map<String, dynamic> json) {
    int? readUserId() {
      for (final key in ['userId', 'id', 'memberId', 'user_id']) {
        final v = json[key];
        if (v == null) continue;
        if (v is int) return v;
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v.toString().trim());
        if (parsed != null) return parsed;
      }
      return null;
    }

    String? readName() {
      for (final key in ['name', 'nickname', 'userName']) {
        final text = json[key]?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }

    String? readProfileImage() {
      final raw =
          json['profileImage'] ?? json['profileImageUrl'] ?? json['imageUrl'];
      final text = raw?.toString().trim();
      return (text != null && text.isNotEmpty) ? text : null;
    }

    String? readRole() {
      final raw = json['role']?.toString().trim().toUpperCase();
      return (raw != null && raw.isNotEmpty) ? raw : null;
    }

    return HouseholdMemberModel(
      userId: readUserId() ?? 0,
      name: readName() ?? '',
      profileImage: readProfileImage(),
      role: readRole(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'profileImage': profileImage,
        'role': role,
      };
}

@JsonSerializable()
class HouseholdResult {
  /// 초대 코드. 서버는 `inviteCode` 또는 레거시 `code`로 줄 수 있음.
  final String? code;
  final String? name; // 그룹명
  final int? id; // 그룹 ID
  final String? role; // 사용자 역할 (LEADER / MEMBER)
  final bool? isLeader;
  final List<HouseholdMemberModel>? members;

  HouseholdResult({
    this.code,
    this.name,
    this.id,
    this.role,
    this.isLeader,
    this.members,
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

    List<HouseholdMemberModel>? parsedMembers;
    final membersRaw = json['members'];
    if (membersRaw is List) {
      final list = <HouseholdMemberModel>[];
      for (final e in membersRaw) {
        if (e is! Map<String, dynamic>) continue;
        final m = HouseholdMemberModel.fromJson(e);
        if (m.userId > 0 && m.name.isNotEmpty) list.add(m);
      }
      if (list.isNotEmpty) parsedMembers = list;
    }

    return HouseholdResult(
      // GET /households/me: inviteCode · 레거시: code / householdCode
      code: readString(['inviteCode', 'code', 'householdCode']),
      name: readString(['name', 'householdName']),
      id: readInt(['id', 'householdId']),
      role: parsedRole,
      isLeader: isLeader,
      members: parsedMembers,
    );
  }

  Map<String, dynamic> toJson() => _$HouseholdResultToJson(this);
}

