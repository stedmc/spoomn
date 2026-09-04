import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spoomn_core/spoomn_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.isPasswordRecovery = false});

  final bool isPasswordRecovery;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _savingName = false;
  bool _uploadingAvatar = false;
  bool _uploadingPawn = false;
  bool _showSignIn = false;
  bool _showNewPasswordCard = false;

  String? _favouriteProperty;
  String? _favouritePartner;
  bool _loadedFavourites = false;

  bool _recoveringFromMissingProfile = false;
  bool _missingProfileRecoveryFailed = false;

  @override
  void initState() {
    super.initState();
    _showNewPasswordCard = widget.isPasswordRecovery;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) unawaited(_loadFavourites(userId));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFavourites(String userId) async {
    if (_loadedFavourites) return;
    _loadedFavourites = true;

    final client = Supabase.instance.client;

    final topProperty = await client
        .from('property_stats')
        .select('square_index, times_owned')
        .eq('profile_id', userId)
        .order('times_owned', ascending: false)
        .limit(1)
        .maybeSingle();

    final topPartner = await client
        .from('trade_stats')
        .select('partner_id, trades_completed')
        .eq('profile_id', userId)
        .order('trades_completed', ascending: false)
        .limit(1)
        .maybeSingle();

    String? partnerName;
    if (topPartner != null) {
      final partnerProfile = await client
          .from('profiles')
          .select('display_name')
          .eq('id', topPartner['partner_id'] as String)
          .maybeSingle();
      partnerName = partnerProfile?['display_name'] as String?;
    }

    if (!mounted) return;
    setState(() {
      _favouriteProperty = topProperty != null
          ? Board.squares[topProperty['square_index'] as int].name
          : null;
      _favouritePartner = partnerName;
    });
  }

  /// Auth session survived but the profile row is gone (e.g. deleted server-side).
  /// Sign out of the orphaned session and start a fresh anonymous one so the
  /// screen falls back to the normal logged-out (create account / sign in) flow.
  Future<void> _recoverFromMissingProfile() async {
    if (_recoveringFromMissingProfile) return;
    _recoveringFromMissingProfile = true;
    try {
      final client = Supabase.instance.client;
      await client.auth.signOut();
      await client.auth.signInAnonymously();
      _loadedFavourites = false;
      _nameController.clear();
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      ref.invalidate(myStatsProvider);
    } catch (_) {
      if (mounted) setState(() => _missingProfileRecoveryFailed = true);
    } finally {
      _recoveringFromMissingProfile = false;
    }
  }

  Future<void> _saveName(String userId) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _savingName) return;
    setState(() => _savingName = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'display_name': name}).eq('id', userId);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _uploadPhoto({
    required String userId,
    required String kind, // 'avatar' or 'pawn'
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => kind == 'avatar' ? _uploadingAvatar = true : _uploadingPawn = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final path = '$userId/$kind.$ext';
      final client = Supabase.instance.client;

      await client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final url = client.storage.from('avatars').getPublicUrl(path);
      // Cache-bust so already-loaded clients (this board's token image cache
      // included) pick up the new photo instead of serving the stale one.
      final bustedUrl = '$url?v=${DateTime.now().millisecondsSinceEpoch}';

      final column = kind == 'avatar' ? 'avatar_url' : 'pawn_photo_url';
      await client.from('profiles').update({column: bustedUrl}).eq('id', userId);
    } finally {
      if (mounted) {
        setState(() => kind == 'avatar' ? _uploadingAvatar = false : _uploadingPawn = false);
      }
    }
  }

  Future<void> _createAccount(String userId, String email, String password) async {
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(email: email, password: password),
    );
    await Supabase.instance.client
        .from('profiles')
        .update({'is_anonymous': false}).eq('id', userId);
  }

  Future<void> _signInExisting(String email, String password) async {
    await Supabase.instance.client.auth.signOut();
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> _sendPasswordReset(String email) async {
    await Supabase.instance.client.auth.resetPasswordForEmail(email);
  }

  Future<void> _setNewPassword(String password) async {
    await Supabase.instance.client.auth
        .updateUser(UserAttributes(password: password));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final statsAsync = ref.watch(myStatsProvider);
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) {
            if (_missingProfileRecoveryFailed) {
              return const Center(child: Text('Profile not found'));
            }
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _recoverFromMissingProfile());
            return const Center(child: CircularProgressIndicator());
          }
          if (_nameController.text.isEmpty) {
            _nameController.text = profile['display_name'] as String? ?? '';
          }
          final isAnonymous = profile['is_anonymous'] as bool? ?? true;
          final avatarUrl = profile['avatar_url'] as String?;
          final pawnUrl = profile['pawn_photo_url'] as String?;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_showNewPasswordCard)
                _SetNewPasswordCard(
                  onSetPassword: _setNewPassword,
                  onDismiss: () => setState(() => _showNewPasswordCard = false),
                ),
              if (_showNewPasswordCard) const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: (_uploadingAvatar || isAnonymous)
                          ? null
                          : () => _uploadPhoto(userId: userId, kind: 'avatar'),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage:
                            avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: _uploadingAvatar
                            ? const CircularProgressIndicator()
                            : (avatarUrl == null
                                ? Icon(isAnonymous ? Icons.lock : Icons.camera_alt, size: 28)
                                : null),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAnonymous ? 'Profile picture — create an account to set' : 'Profile picture',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: (_uploadingPawn || isAnonymous)
                        ? null
                        : () => _uploadPhoto(userId: userId, kind: 'pawn'),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: pawnUrl != null ? NetworkImage(pawnUrl) : null,
                      child: _uploadingPawn
                          ? const CircularProgressIndicator()
                          : (pawnUrl == null
                              ? Icon(isAnonymous ? Icons.lock : Icons.add_a_photo, size: 20)
                              : null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAnonymous
                          ? 'Pawn photo — create an account to set a photo for your board token'
                          : 'Pawn photo — shown on the board instead of a plain token',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                maxLength: 50,
                decoration: InputDecoration(
                  labelText: 'Display name',
                  suffixIcon: _savingName
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.check),
                          onPressed: () => _saveName(userId),
                        ),
                ),
                onSubmitted: (_) => _saveName(userId),
              ),
              const SizedBox(height: 24),
              if (isAnonymous)
                _AccountUpgradeCard(
                  showSignIn: _showSignIn,
                  onToggleSignIn: () => setState(() => _showSignIn = !_showSignIn),
                  onCreateAccount: (email, pass) => _createAccount(userId, email, pass),
                  onSignIn: _signInExisting,
                  onForgotPassword: _sendPasswordReset,
                )
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.verified_user),
                    title: Text(Supabase.instance.client.auth.currentUser?.email ?? 'Named account'),
                    subtitle: const Text('Stats and games sync across devices'),
                  ),
                ),
              const SizedBox(height: 24),
              Text('Stats', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              statsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (stats) => _StatsGrid(
                  stats: stats,
                  favouriteProperty: _favouriteProperty,
                  favouritePartner: _favouritePartner,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.stats,
    required this.favouriteProperty,
    required this.favouritePartner,
  });

  final Map<String, dynamic>? stats;
  final String? favouriteProperty;
  final String? favouritePartner;

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return const Text('No games played yet', style: TextStyle(color: Colors.grey));
    }
    final games = stats!['games_played'] as int? ?? 0;
    final wins = stats!['wins'] as int? ?? 0;
    final winRate = games > 0 ? '${(wins / games * 100).round()}%' : '—';

    final entries = <(String, String)>[
      ('Games played', '$games'),
      ('Wins', '$wins'),
      ('Losses', '${stats!['losses'] ?? 0}'),
      ('Win rate', winRate),
      ('Avg. placement', (stats!['avg_placement'] as num?)?.toStringAsFixed(1) ?? '—'),
      ('Peak net worth', '£${stats!['peak_net_worth'] ?? 0}'),
      ('Bankruptcies', '${stats!['bankruptcies'] ?? 0}'),
      ('Properties bought', '${stats!['properties_bought'] ?? 0}'),
      ('Monopolies completed', '${stats!['monopolies_completed'] ?? 0}'),
      ('Jail visits', '${stats!['jail_visits'] ?? 0}'),
      ('Tax paid', '£${stats!['tax_paid_total'] ?? 0}'),
      (
        'Fastest win',
        stats!['fastest_win_turns'] != null ? '${stats!['fastest_win_turns']} turns' : '—'
      ),
      ('Favourite property', favouriteProperty ?? '—'),
      ('Favourite trading partner', favouritePartner ?? '—'),
    ];

    return Column(
      children: entries
          .map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.$1, style: const TextStyle(color: Colors.grey)),
                    Text(e.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _AccountUpgradeCard extends StatefulWidget {
  const _AccountUpgradeCard({
    required this.showSignIn,
    required this.onToggleSignIn,
    required this.onCreateAccount,
    required this.onSignIn,
    required this.onForgotPassword,
  });

  final bool showSignIn;
  final VoidCallback onToggleSignIn;
  final Future<void> Function(String email, String password) onCreateAccount;
  final Future<void> Function(String email, String password) onSignIn;
  final Future<void> Function(String email) onForgotPassword;

  @override
  State<_AccountUpgradeCard> createState() => _AccountUpgradeCardState();
}

class _AccountUpgradeCardState extends State<_AccountUpgradeCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _sendingReset = false;
  bool _resetSent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.showSignIn) {
        await widget.onSignIn(_email.text.trim(), _password.text);
      } else {
        await widget.onCreateAccount(_email.text.trim(), _password.text);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || _sendingReset) return;
    setState(() {
      _sendingReset = true;
      _error = null;
    });
    try {
      await widget.onForgotPassword(email);
      if (mounted) setState(() => _resetSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.showSignIn ? 'Sign in to your account' : 'Save your stats permanently',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              widget.showSignIn
                  ? 'Signing in switches away from this guest session — its stats stay with the guest.'
                  : "You're playing as a guest. Add an email and password to keep your stats across devices.",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (widget.showSignIn)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _sendingReset ? null : _forgotPassword,
                  child: _sendingReset
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_resetSent ? 'Reset email sent' : 'Forgotten password?'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.showSignIn ? 'Sign In' : 'Create Account'),
            ),
            TextButton(
              onPressed: widget.onToggleSignIn,
              child: Text(widget.showSignIn
                  ? 'Create a new account instead'
                  : 'Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetNewPasswordCard extends StatefulWidget {
  const _SetNewPasswordCard({
    required this.onSetPassword,
    required this.onDismiss,
  });

  final Future<void> Function(String password) onSetPassword;
  final VoidCallback onDismiss;

  @override
  State<_SetNewPasswordCard> createState() => _SetNewPasswordCardState();
}

class _SetNewPasswordCardState extends State<_SetNewPasswordCard> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSetPassword(_password.text);
      if (mounted) widget.onDismiss();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Set a new password', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save password'),
            ),
          ],
        ),
      ),
    );
  }
}
