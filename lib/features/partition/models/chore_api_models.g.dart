// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chore_api_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChoreMutationResponseModel _$ChoreMutationResponseModelFromJson(
        Map<String, dynamic> json) =>
    ChoreMutationResponseModel(
      isSuccess: json['isSuccess'] as bool,
      code: choreApiString(json['code']),
      message: json['message'] as String,
      result: json['result'] == null
          ? null
          : ChoreApiDetail.fromJson(json['result'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );

Map<String, dynamic> _$ChoreMutationResponseModelToJson(
        ChoreMutationResponseModel instance) =>
    <String, dynamic>{
      'isSuccess': instance.isSuccess,
      'code': instance.code,
      'message': instance.message,
      'result': instance.result,
      'error': instance.error,
    };

ChoreApiDetail _$ChoreApiDetailFromJson(Map<String, dynamic> json) =>
    ChoreApiDetail(
      choreId: choreApiInt(json['choreId']),
      assigneeId: choreApiInt(json['assigneeId']),
      assigneeName: json['assigneeName'] as String,
      choreType: json['choreType'] as String,
      choreName: json['choreName'] as String,
      date: json['date'] as String,
      isCompleted: choreApiBool(json['isCompleted']),
    );

Map<String, dynamic> _$ChoreApiDetailToJson(ChoreApiDetail instance) =>
    <String, dynamic>{
      'choreId': instance.choreId,
      'assigneeId': instance.assigneeId,
      'assigneeName': instance.assigneeName,
      'choreType': instance.choreType,
      'choreName': instance.choreName,
      'date': instance.date,
      'isCompleted': instance.isCompleted,
    };

ChoreDailyListResponseModel _$ChoreDailyListResponseModelFromJson(
        Map<String, dynamic> json) =>
    ChoreDailyListResponseModel(
      isSuccess: json['isSuccess'] as bool,
      code: choreApiString(json['code']),
      message: json['message'] as String,
      result: (json['result'] as List<dynamic>?)
          ?.map((e) => ChoreDailyApiItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );

Map<String, dynamic> _$ChoreDailyListResponseModelToJson(
        ChoreDailyListResponseModel instance) =>
    <String, dynamic>{
      'isSuccess': instance.isSuccess,
      'code': instance.code,
      'message': instance.message,
      'result': instance.result,
      'error': instance.error,
    };

ChoreDailyApiItem _$ChoreDailyApiItemFromJson(Map<String, dynamic> json) =>
    ChoreDailyApiItem(
      choreId: choreApiInt(json['choreId']),
      assigneeId: choreApiInt(json['assigneeId']),
      assigneeName: json['assigneeName'] as String,
      assigneeProfileImage: json['assigneeProfileImage'] as String?,
      choreType: json['choreType'] as String,
      choreName: json['choreName'] as String,
      date: json['date'] as String,
      isCompleted: choreApiBool(json['isCompleted']),
    );

Map<String, dynamic> _$ChoreDailyApiItemToJson(ChoreDailyApiItem instance) =>
    <String, dynamic>{
      'choreId': instance.choreId,
      'assigneeId': instance.assigneeId,
      'assigneeName': instance.assigneeName,
      'assigneeProfileImage': instance.assigneeProfileImage,
      'choreType': instance.choreType,
      'choreName': instance.choreName,
      'date': instance.date,
      'isCompleted': instance.isCompleted,
    };
