/// `GET /api/reservations` · `POST /api/reservations` 응답 모델

class ReservedBy {
  final int userId;
  final String name;

  const ReservedBy({
    required this.userId,
    required this.name,
  });

  factory ReservedBy.fromJson(Map<String, dynamic> json) {
    return ReservedBy(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
    );
  }
}

/// 목록 조회 `result[]` 항목
class ReservationListEntry {
  final int reservationId;
  final int itemId;
  final String itemName;
  final DateTime startTime;
  final DateTime endTime;
  final bool isCompleted;
  final ReservedBy? reservedBy;

  const ReservationListEntry({
    required this.reservationId,
    required this.itemId,
    required this.itemName,
    required this.startTime,
    required this.endTime,
    this.isCompleted = false,
    this.reservedBy,
  });

  factory ReservationListEntry.fromJson(Map<String, dynamic> json) {
    final startRaw = json['startTime'] as String?;
    final endRaw = json['endTime'] as String?;
    return ReservationListEntry(
      reservationId: (json['reservationId'] as num?)?.toInt() ?? 0,
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      startTime: startRaw != null ? DateTime.parse(startRaw) : DateTime(1970),
      endTime: endRaw != null ? DateTime.parse(endRaw) : DateTime(1970),
      isCompleted: json['isCompleted'] == true,
      reservedBy: json['reservedBy'] is Map<String, dynamic>
          ? ReservedBy.fromJson(json['reservedBy'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// `PATCH /api/reservations/{reservationId}/complete` 성공 시 `result`
class ReservationCompleted {
  final int reservationId;
  final bool isCompleted;
  final DateTime endTime;

  const ReservationCompleted({
    required this.reservationId,
    required this.isCompleted,
    required this.endTime,
  });

  factory ReservationCompleted.fromJson(Map<String, dynamic> json) {
    final endRaw = json['endTime'] as String?;
    return ReservationCompleted(
      reservationId: (json['reservationId'] as num?)?.toInt() ?? 0,
      isCompleted: json['isCompleted'] == true,
      endTime: endRaw != null ? DateTime.parse(endRaw) : DateTime(1970),
    );
  }
}

/// 예약 등록 `POST` 성공 시 `result`
class ReservationCreated {
  final int reservationId;
  final int itemId;
  final String itemName;
  final DateTime startTime;
  final DateTime endTime;
  final ReservedBy? reservedBy;

  const ReservationCreated({
    required this.reservationId,
    required this.itemId,
    required this.itemName,
    required this.startTime,
    required this.endTime,
    this.reservedBy,
  });

  factory ReservationCreated.fromJson(Map<String, dynamic> json) {
    final startRaw = json['startTime'] as String?;
    final endRaw = json['endTime'] as String?;
    return ReservationCreated(
      reservationId: (json['reservationId'] as num?)?.toInt() ?? 0,
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      startTime: startRaw != null ? DateTime.parse(startRaw) : DateTime(1970),
      endTime: endRaw != null ? DateTime.parse(endRaw) : DateTime(1970),
      reservedBy: json['reservedBy'] is Map<String, dynamic>
          ? ReservedBy.fromJson(json['reservedBy'] as Map<String, dynamic>)
          : null,
    );
  }
}
