// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_calendar_response_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DailyCalendarResponseModel _$DailyCalendarResponseModelFromJson(
        Map<String, dynamic> json) =>
    DailyCalendarResponseModel(
      isSuccess: json['isSuccess'] as bool,
      code: dailyCalendarApiString(json['code']),
      message: json['message'] as String,
      result: (json['result'] as List<dynamic>?)
          ?.map((e) => DailyCalendarItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );

Map<String, dynamic> _$DailyCalendarResponseModelToJson(
        DailyCalendarResponseModel instance) =>
    <String, dynamic>{
      'isSuccess': instance.isSuccess,
      'code': instance.code,
      'message': instance.message,
      'result': instance.result,
      'error': instance.error,
    };

Map<String, dynamic> _$DailyCalendarItemToJson(DailyCalendarItem instance) =>
    <String, dynamic>{
      'category': instance.category,
      'id': instance.id,
      'title': instance.title,
      'assigneeName': instance.assigneeName,
      'assigneeId': instance.assigneeId,
      'choreType': instance.choreType,
      'isCompleted': instance.isCompleted,
      'isOwner': instance.isOwner,
    };
