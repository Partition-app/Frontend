import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:partition_app/features/auth/models/household_response_model.dart';
import 'package:partition_app/features/auth/services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _errorMessage;
  HouseholdResult? _household;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadHousehold();
  }

  Future<void> _loadHousehold() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _authService.fetchMyHousehold(),
        _authService.getResolvedCurrentUserId(),
      ]);
      if (!mounted) return;

      final response = results[0] as HouseholdResponseModel?;
      final uid = results[1] as int?;

      if (response == null) {
        // 그룹 미소속(HOUSEHOLD_4001) 또는 통신 실패 모두 빈 상태로 표시
        setState(() {
          _household = null;
          _currentUserId = uid;
          _loading = false;
          _errorMessage = null;
        });
        return;
      }

      if (response.isSuccess) {
        setState(() {
          _household = response.result;
          _currentUserId = uid;
          _loading = false;
        });
        return;
      }

      // HOUSEHOLD_4001: 소속된 그룹이 없습니다.
      final message = response.message.trim().isNotEmpty
          ? response.message
          : '소속된 그룹이 없습니다.';
      setState(() {
        _household = null;
        _currentUserId = uid;
        _loading = false;
        _errorMessage = response.code == 'HOUSEHOLD_4001'
            ? null // 그룹 미소속은 에러가 아닌 빈 상태로 표시
            : message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _household = null;
        _loading = false;
        _errorMessage = '그룹 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대 코드를 복사했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadHousehold,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHousehold,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _buildHouseholdSection(),
            const Divider(height: 24),
            const ListTile(
              leading: Icon(Icons.info),
              title: Text('앱 정보'),
              subtitle: Text('버전 1.0.0'),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                '로그아웃',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                // TODO: 로그아웃 기능 구현
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadHousehold,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final household = _household;
    if (household == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '현재 소속된 그룹이 없거나 그룹 정보를 불러오지 못했습니다.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadHousehold,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final name = household.name?.trim().isNotEmpty == true
        ? household.name!.trim()
        : '이름 없는 그룹';
    final inviteCode = household.code?.trim();
    final members = household.members ?? const <HouseholdMemberModel>[];
    final leader = members.firstWhere(
      (m) => (m.role ?? '').toUpperCase() == 'LEADER',
      orElse: () => const HouseholdMemberModel(userId: 0, name: ''),
    );
    final leaderName = leader.userId > 0 ? leader.name : null;
    final isLeader = household.isLeader == true ||
        (household.role ?? '').toUpperCase() == 'LEADER';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('그룹 정보'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.home_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isLeader)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '내가 방장',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoRow(
                    label: '방장',
                    value: leaderName ?? '정보 없음',
                  ),
                  const SizedBox(height: 6),
                  _infoRow(
                    label: '그룹원',
                    value: '${members.length}명',
                  ),
                  if (inviteCode != null && inviteCode.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            '초대 코드',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            inviteCode,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _copyInviteCode(inviteCode),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('복사'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionHeader('그룹원 (${members.length}명)'),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              '표시할 그룹원이 없습니다.',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          ...members.map(_buildMemberTile),
      ],
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTile(HouseholdMemberModel m) {
    final role = (m.role ?? '').toUpperCase();
    final isLeader = role == 'LEADER';
    final isMe = _currentUserId != null && _currentUserId == m.userId;
    final imageUrl = m.profileImage?.trim();
    final hasImage = imageUrl != null &&
        imageUrl.isNotEmpty &&
        (imageUrl.startsWith('http://') || imageUrl.startsWith('https://'));

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
        child: hasImage
            ? null
            : Text(
                m.name.isNotEmpty ? m.name.characters.first : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              m.name.isNotEmpty ? m.name : '이름 없음',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            _chip('나', background: Colors.blue.shade50, foreground: Colors.blue.shade700),
          ],
        ],
      ),
      subtitle: Text(
        isLeader ? '방장' : '그룹원',
        style: TextStyle(
          fontSize: 12,
          color: isLeader ? Colors.amber.shade800 : Colors.grey.shade600,
          fontWeight: isLeader ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isLeader
          ? Icon(Icons.workspace_premium, color: Colors.amber.shade700)
          : null,
    );
  }

  Widget _chip(String text,
      {required Color background, required Color foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
