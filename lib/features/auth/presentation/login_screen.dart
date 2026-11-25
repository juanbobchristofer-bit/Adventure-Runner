import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';

/// Halaman Login & Pendaftaran yang fleksibel: mendukung Masuk, Daftar, Lupa Password,
/// serta opsi Lanjut Mode Offline (Tamu) tanpa memaksa pengguna membuat akun.
class LoginScreen extends StatefulWidget {
  /// Jika `true`, tombol "Lanjut Mode Offline" menyimpan preferensi tamu & memanggil [onAuthComplete].
  /// Jika `false` (dibuka sebagai modal dari tab Grup/Profil), layar ini akan `Navigator.pop(context, true)` setelah login.
  final bool isInitialGate;
  final VoidCallback? onAuthComplete;

  const LoginScreen({
    super.key,
    this.isInitialGate = false,
    this.onAuthComplete,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _isSignUpMode = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();

    if (_isSignUpMode && name.isEmpty) {
      _showSnack('Masukkan nama pelari Anda terlebih dahulu.', isError: true);
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Masukkan alamat email yang valid.', isError: true);
      return;
    }
    if (password.length < 6) {
      _showSnack('Password minimal 6 karakter.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final result = _isSignUpMode
        ? await AuthService.signUpWithEmail(displayName: name, email: email, password: password)
        : await AuthService.signInWithEmail(email: email, password: password);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    _showSnack(result.message, isError: !result.success);

    if (result.success) {
      if (result.requiresEmailConfirmation) {
        setState(() => _isSignUpMode = false);
      } else {
        await AuthService.continueAsGuest();
        if (!mounted) return;
        if (widget.onAuthComplete != null) {
          widget.onAuthComplete!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      }
    }
  }

  Future<void> _continueOffline() async {
    await AuthService.continueAsGuest();
    if (!mounted) return;
    if (widget.onAuthComplete != null) {
      widget.onAuthComplete!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context, false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetCtrl = TextEditingController(text: _emailCtrl.text.trim());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: resetCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Masukkan email akun Anda',
            hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            filled: true,
            fillColor: AppColors.backgroundDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () async {
              final email = resetCtrl.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              final res = await AuthService.sendPasswordReset(email);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) _showSnack(res.message, isError: !res.success);
            },
            child: const Text('Kirim Tautan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    resetCtrl.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppColors.cardElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: widget.isInitialGate
          ? null
          : AppBar(
              backgroundColor: AppColors.backgroundDark,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context, false),
              ),
              title: const Text(
                'Akun Komunitas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Header
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryOrange, AppColors.primaryOrangeLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryOrange.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.bolt, color: Colors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ADVENTURE RUNNER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Masuk untuk ikut Klub, Acara & Leaderboard online, atau lanjut offline kapan saja.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 26),

                // Mode Switcher (Masuk / Daftar)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      _buildModeTab('Masuk', !_isSignUpMode, () => setState(() => _isSignUpMode = false)),
                      _buildModeTab('Daftar Baru', _isSignUpMode, () => setState(() => _isSignUpMode = true)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Form Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      if (_isSignUpMode) ...[
                        _buildInput(
                          controller: _nameCtrl,
                          label: 'Nama Pelari',
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildInput(
                        controller: _emailCtrl,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                        controller: _passwordCtrl,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                            size: 19,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      if (!_isSignUpMode) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                            child: const Text(
                              'Lupa Password?',
                              style: TextStyle(color: AppColors.primaryOrangeLight, fontSize: 12),
                            ),
                          ),
                        ),
                      ] else
                        const SizedBox(height: 16),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryOrange,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : Text(
                                  _isSignUpMode ? 'Buat Akun & Gabung' : 'Masuk Sekarang',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white12)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('atau fleksibel tanpa login', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    ),
                    Expanded(child: Divider(color: Colors.white12)),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _continueOffline,
                    icon: const Icon(Icons.offline_bolt_outlined, color: AppColors.accentGreen, size: 19),
                    label: Text(
                      widget.isInitialGate ? 'Lanjut Mode Offline (Tamu)' : 'Nanti Saja (Tetap Offline)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        prefixIcon: Icon(icon, color: AppColors.primaryOrange, size: 19),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
