import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:partition_app/core/config/app_config.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String formattedAddress;
  final double lat;
  final double lng;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
  });
}

/// 카카오 검색 결과 래퍼 — 결과 목록과 에러 메시지를 함께 반환
typedef SearchResult = ({List<PlaceSuggestion> results, String? error});

/// 역지오코딩 결과 — [error] 는 카카오 인증·권한 오류 등 사용자 안내용
typedef ReverseGeocodeResult = ({String? address, String? error});

typedef _KakaoCoordFetch = ({
  String? line,
  int httpStatus,
  String? bodySnippet,
});

class GeocodingService {
  /// 카카오 REST API 키 유효성 확인
  static bool get hasApiKey {
    const k = AppConfig.kakaoRestApiKey;
    return k.isNotEmpty && k != 'YOUR_KAKAO_REST_API_KEY';
  }

  // ── 역지오코딩 (좌표 → 주소) ─────────────────────────────────────────────

  /// 위도·경도 → 주소 문자열
  /// 카카오 coord2address API 우선, 실패 시 기기 내장 지오코더 폴백
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final r = await reverseGeocodeWithDetails(lat, lng);
    return r.address;
  }

  /// 역지오코딩과 함께 실패 원인(카카오맵 미활성·키 오류 등)을 받을 때 사용합니다.
  static Future<ReverseGeocodeResult> reverseGeocodeWithDetails(
      double lat, double lng) async {
    String? kakaoAuthError;

    if (hasApiKey) {
      final kakao = await _kakaoReverseGeocodeWithAuthInfo(lat, lng);
      if (kakao.address != null) {
        return (address: kakao.address, error: null);
      }
      kakaoAuthError = kakao.error;
    }

    final deviceAddr = await _deviceReverseGeocode(lat, lng);
    if (deviceAddr != null) {
      return (address: deviceAddr, error: null);
    }

    if (!hasApiKey) {
      return (
        address: null,
        error: '카카오 REST API 키가 없어 역지오코딩과 검색을 쓸 수 없어요.',
      );
    }
    return (
      address: null,
      error: kakaoAuthError,
    );
  }

  /// (`address`, `error`) — [error] 는 HTTP 401/403 등에만 채워집니다.
  static Future<({String? address, String? error})>
      _kakaoReverseGeocodeWithAuthInfo(double lat, double lng) async {
    final coord2Addr = await _fetchCoord2Address(lat, lng);
    if (coord2Addr.line != null) {
      return (address: coord2Addr.line, error: null);
    }
    if (_isKakaoAuthFailure(coord2Addr.httpStatus)) {
      debugPrint('[GeocodingService] coord2address 오류: ${coord2Addr.bodySnippet}');
      return (
        address: null,
        error: _kakaoReverseFailureMessage(coord2Addr.httpStatus),
      );
    }

    final region = await _fetchCoord2RegionCode(lat, lng);
    if (region.line != null) {
      return (address: region.line, error: null);
    }
    if (_isKakaoAuthFailure(region.httpStatus)) {
      debugPrint(
          '[GeocodingService] coord2regioncode 오류: ${region.bodySnippet}');
      return (
        address: null,
        error: _kakaoReverseFailureMessage(region.httpStatus),
      );
    }

    return (address: null, error: null);
  }

  static bool _isKakaoAuthFailure(int status) =>
      status == 401 || status == 403;

  static String _kakaoReverseFailureMessage(int status) {
    if (status == 401) {
      return 'API 키 인증 실패 — REST API 키와 앱 플랫폼(번들 ID·패키지명)을 확인해주세요.';
    }
    if (status == 403) {
      return '카카오맵 API가 꺼져 있거나 호출이 거절됐어요.\n'
          '카카오 개발자 콘솔 → 해당 앱 → 제품 설정 → 카카오맵 → 사용 설정 ON\n'
          '(푸시 「API 호출 에러」와 동일한 경우가 많아요.)';
    }
    return '주소 변환 오류 (HTTP $status)';
  }

  /// /v2/local/geo/coord2address.json — 도로명주소 우선, 없으면 지번주소
  static Future<_KakaoCoordFetch> _fetchCoord2Address(
      double lat, double lng) async {
    try {
      final uri = Uri.https(
        'dapi.kakao.com',
        '/v2/local/geo/coord2address.json',
        {'x': '$lng', 'y': '$lat'},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}'},
      );
      debugPrint('[GeocodingService] coord2address 응답: ${response.statusCode}');
      final code = response.statusCode;
      if (code != 200) {
        return (
          line: null,
          httpStatus: code,
          bodySnippet: _truncateBody(response.body),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>;
      if (docs.isEmpty) {
        return (line: null, httpStatus: 200, bodySnippet: null);
      }

      final doc = docs.first as Map<String, dynamic>;
      final roadAddress = doc['road_address'] as Map<String, dynamic>?;
      if (roadAddress != null) {
        final name = roadAddress['address_name'] as String?;
        if (name != null && name.isNotEmpty) {
          return (line: name, httpStatus: 200, bodySnippet: null);
        }
      }
      final address = doc['address'] as Map<String, dynamic>?;
      final lot = address?['address_name'] as String?;
      return (line: lot, httpStatus: 200, bodySnippet: null);
    } catch (e) {
      debugPrint('[GeocodingService] coord2address 예외: $e');
      return (line: null, httpStatus: -1, bodySnippet: e.toString());
    }
  }

  /// /v2/local/geo/coord2regioncode.json — 행정동(H) 주소
  static Future<_KakaoCoordFetch> _fetchCoord2RegionCode(
      double lat, double lng) async {
    try {
      final uri = Uri.https(
        'dapi.kakao.com',
        '/v2/local/geo/coord2regioncode.json',
        {'x': '$lng', 'y': '$lat'},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}'},
      );
      debugPrint(
          '[GeocodingService] coord2regioncode 응답: ${response.statusCode}');
      final code = response.statusCode;
      if (code != 200) {
        return (
          line: null,
          httpStatus: code,
          bodySnippet: _truncateBody(response.body),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>;
      if (docs.isEmpty) {
        return (line: null, httpStatus: 200, bodySnippet: null);
      }

      for (final d in docs) {
        final doc = d as Map<String, dynamic>;
        if (doc['region_type'] == 'H') {
          final name = doc['address_name'] as String?;
          if (name != null && name.isNotEmpty) {
            return (line: name, httpStatus: 200, bodySnippet: null);
          }
        }
      }
      final firstName =
          (docs.first as Map<String, dynamic>)['address_name'] as String?;
      return (line: firstName, httpStatus: 200, bodySnippet: null);
    } catch (e) {
      debugPrint('[GeocodingService] coord2regioncode 예외: $e');
      return (line: null, httpStatus: -1, bodySnippet: e.toString());
    }
  }

  static String? _truncateBody(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;

  static Future<String?> _deviceReverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = <String>[
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
          p.administrativeArea!,
        if (p.subAdministrativeArea != null &&
            p.subAdministrativeArea!.isNotEmpty)
          p.subAdministrativeArea!
        else if (p.locality != null && p.locality!.isNotEmpty)
          p.locality!,
        if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty)
          p.thoroughfare!
        else if (p.subLocality != null && p.subLocality!.isNotEmpty)
          p.subLocality!,
        if (p.subThoroughfare != null && p.subThoroughfare!.isNotEmpty)
          p.subThoroughfare!,
      ];
      return parts.isNotEmpty ? parts.join(' ') : null;
    } catch (e) {
      debugPrint('[GeocodingService] 기기 역지오코딩 실패: $e');
      return null;
    }
  }

  // ── 주소 검색 (카카오 키워드 + 도로명·지번 주소) ───────────────────────────

  /// 키워드로 장소 검색 (카카오 Local keyword API)
  static Future<SearchResult> _searchKeywordPlaces(String query) async {
    if (query.trim().isEmpty) {
      return (results: <PlaceSuggestion>[], error: null);
    }
    if (!hasApiKey) {
      return (
        results: <PlaceSuggestion>[],
        error: '카카오 REST API 키가 설정되지 않았어요.'
      );
    }

    try {
      final uri = Uri.https(
        'dapi.kakao.com',
        '/v2/local/search/keyword.json',
        {'query': query, 'size': '7'},
      );
      debugPrint('[GeocodingService] 키워드 검색 → $uri');

      final response = await http.get(
        uri,
        headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}'},
      );

      debugPrint('[GeocodingService] 키워드 응답: ${response.statusCode}');

      if (response.statusCode != 200) {
        return (
          results: <PlaceSuggestion>[],
          error: _parseKakaoSearchError(response.statusCode, response.body),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>;
      debugPrint('[GeocodingService] 키워드 결과: ${docs.length}건');

      final suggestions = docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final placeName = (doc['place_name'] as String?) ?? '';
        final roadAddr = (doc['road_address_name'] as String?) ?? '';
        final lotAddr = (doc['address_name'] as String?) ?? '';
        final displayAddr = roadAddr.isNotEmpty ? roadAddr : lotAddr;

        return PlaceSuggestion(
          placeId: (doc['id'] as String?) ?? '',
          mainText: placeName.isNotEmpty ? placeName : displayAddr,
          secondaryText: placeName.isNotEmpty ? displayAddr : '',
          formattedAddress:
              placeName.isNotEmpty ? '$placeName ($displayAddr)' : displayAddr,
          lat: double.tryParse(doc['y'] as String? ?? '') ?? 0,
          lng: double.tryParse(doc['x'] as String? ?? '') ?? 0,
        );
      }).toList();

      return (results: suggestions, error: null);
    } catch (e) {
      debugPrint('[GeocodingService] 키워드 검색 예외: $e');
      return (results: <PlaceSuggestion>[], error: '네트워크 오류: $e');
    }
  }

  /// 도로명·지번 주소 문자열 검색 (카카오 Local address API)
  ///
  /// 키워드 API는 등록된 「장소」 위주라, 명칭 없는 도로명주소만으로는 결과가 없을 수 있습니다.
  static Future<SearchResult> _searchAddressDocuments(String query) async {
    if (query.trim().isEmpty) {
      return (results: <PlaceSuggestion>[], error: null);
    }
    if (!hasApiKey) {
      return (results: <PlaceSuggestion>[], error: null);
    }

    try {
      final uri = Uri.https(
        'dapi.kakao.com',
        '/v2/local/search/address.json',
        {'query': query, 'size': '10'},
      );
      debugPrint('[GeocodingService] 주소 검색 → $uri');

      final response = await http.get(
        uri,
        headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}'},
      );
      debugPrint('[GeocodingService] 주소 응답: ${response.statusCode}');

      if (response.statusCode != 200) {
        return (
          results: <PlaceSuggestion>[],
          error: _parseKakaoSearchError(response.statusCode, response.body),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>;
      debugPrint('[GeocodingService] 주소 결과: ${docs.length}건');

      final suggestions = <PlaceSuggestion>[];
      var index = 0;
      for (final d in docs) {
        final doc = d as Map<String, dynamic>;
        final addressName = (doc['address_name'] as String?) ?? '';
        final roadMap = doc['road_address'] as Map<String, dynamic>?;
        final roadLine = (roadMap?['address_name'] as String?) ?? '';
        final y = doc['y'] as String?;
        final x = doc['x'] as String?;
        final lat = double.tryParse(y ?? '') ?? 0;
        final lng = double.tryParse(x ?? '') ?? 0;
        if (lat == 0 && lng == 0) continue;

        final mainLine =
            roadLine.isNotEmpty ? roadLine : addressName;
        if (mainLine.isEmpty) continue;

        final secondary = roadLine.isNotEmpty &&
                addressName.isNotEmpty &&
                addressName != roadLine
            ? addressName
            : '';

        suggestions.add(
          PlaceSuggestion(
            placeId: 'addr_${index++}_${lat}_$lng',
            mainText: mainLine,
            secondaryText: secondary,
            formattedAddress:
                roadLine.isNotEmpty ? roadLine : addressName,
            lat: lat,
            lng: lng,
          ),
        );
      }

      return (results: suggestions, error: null);
    } catch (e) {
      debugPrint('[GeocodingService] 주소 검색 예외: $e');
      return (results: <PlaceSuggestion>[], error: '네트워크 오류: $e');
    }
  }

  static String _parseKakaoSearchError(int statusCode, String body) {
    var errorMsg = '검색 오류 ($statusCode)';
    try {
      final errData = json.decode(body) as Map<String, dynamic>;
      final msg = errData['msg'] as String?;
      final code = errData['code'];
      if (msg != null) errorMsg = '$msg (code: $code)';
    } catch (_) {}

    if (statusCode == 401) {
      return 'API 키 인증 실패 — REST API 키를 확인해주세요.';
    }
    if (statusCode == 403) {
      return 'API 권한 없음 — 제품 설정 → 카카오맵 사용 설정을 ON으로 해주세요.\n'
          '(푸시로 온 카카오맵 오류 안내와 같을 수 있어요.)';
    }
    return errorMsg;
  }

  /// 근접 좌표는 하나로 취급 (키워드·주소 API 중복 제거)
  static bool _sameLocation(PlaceSuggestion a, PlaceSuggestion b) =>
      (a.lat - b.lat).abs() < 1e-5 && (a.lng - b.lng).abs() < 1e-5;

  static List<PlaceSuggestion> _mergePlaceSuggestions(
    List<PlaceSuggestion> keywordFirst,
    List<PlaceSuggestion> addressNext, {
    int maxItems = 12,
  }) {
    final out = <PlaceSuggestion>[];
    void tryAdd(PlaceSuggestion p) {
      if (out.length >= maxItems) return;
      if (p.lat == 0 && p.lng == 0) return;
      final dup = out.any((e) => _sameLocation(e, p));
      if (!dup) out.add(p);
    }

    for (final p in keywordFirst) {
      tryAdd(p);
    }
    for (final p in addressNext) {
      tryAdd(p);
    }
    return out;
  }

  /// 장소(키워드) + 도로명·지번 주소를 함께 검색합니다.
  ///
  /// 반환: (results, error) — 두 API 모두 실패할 때만 [error] 를 우선 반환합니다.
  static Future<SearchResult> searchPlaces(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (results: <PlaceSuggestion>[], error: null);
    }
    if (!hasApiKey) {
      return (
        results: <PlaceSuggestion>[],
        error: '카카오 REST API 키가 설정되지 않았어요.'
      );
    }

    final results = await Future.wait([
      _searchKeywordPlaces(q),
      _searchAddressDocuments(q),
    ]);
    final keyword = results[0];
    final address = results[1];

    final merged = _mergePlaceSuggestions(
      keyword.results,
      address.results,
      maxItems: 12,
    );

    final error = keyword.error ?? address.error;
    if (merged.isEmpty && error != null) {
      return (results: merged, error: error);
    }

    return (results: merged, error: null);
  }
}
