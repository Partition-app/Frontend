// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household_response_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HouseholdResponseModel _$HouseholdResponseModelFromJson(
        Map<String, dynamic> json) =>
    HouseholdResponseModel(
      isSuccess: json['isSuccess'] as bool,
      code: json['code'] as String,
      message: json['message'] as String,
      result: json['result'] == null
          ? null
          : HouseholdResult.fromJson(json['result'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );

Map<String, dynamic> _$HouseholdResponseModelToJson(
        HouseholdResponseModel instance) =>
    <String, dynamic>{
      'isSuccess': instance.isSuccess,
      'code': instance.code,
      'message': instance.message,
      'result': instance.result,
      'error': instance.error,
    };

HouseholdResult _$HouseholdResultFromJson(Map<String, dynamic> json) =>
    HouseholdResult(
      code: json['code'] as String?,
      name: json['name'] as String?,
      id: (json['id'] as num?)?.toInt(),
      role: json['role'] as String?,
      isLeader: json['isLeader'] as bool?,
      members: (json['members'] as List<dynamic>?)
          ?.map((e) =>
              HouseholdMemberModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$HouseholdResultToJson(HouseholdResult instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'id': instance.id,
      'role': instance.role,
      'isLeader': instance.isLeader,
      'members': instance.members,
    };
