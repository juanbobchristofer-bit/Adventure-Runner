import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/run_storage_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dark_osm_tile_layer.dart';
import '../domain/run_model.dart';

/// Layar pasca-lari untuk mengisi judul, catatan, vibe, foto momen, lalu menyimpan aktivitas.
class PostRunActivityScreen extends StatefulWidget {
  final String defaultTitle;
  final double distanceInKm;
  final int durationInSeconds;
  final String pace;
  final int steps;
  final double calories;
  final double elevationGainM;
  final List<LatLng> routePoints;
  final List<RunTrackPoint> trackPoints;

  const PostRunActivityScreen({
    super.key,
    required this.defaultTitle,
    required this.distanceInKm,
    required this.durationInSeconds,
    required this.pace,
    required this.steps,
    required this.calories,
    required this.elevationGainM,
    required this.routePoints,
    required this.trackPoints,
  });

  @override
  State<PostRunActivityScreen> createState() => _PostRunActivityScreenState();
}

class _PostRunActivityScreenState extends State<PostRunActivityScreen> {
  final RunStorageService _storageService = RunStorageService();
  final ImagePicker _picker = ImagePicker();
  final MapController _previewMapController = MapController();

  late TextEditingController _titleController;
  final TextEditingController _notesController = TextEditingController();

  File? _selectedPhoto;
  bool _isSaving = false;

  static const List<String> _feelings = [
    'Luar Biasa 🔥',
    'Santai & Segar 🌿',
    'Kuat & Stabil 💪',
    'Tanjakan Berat ⛰️',
    'Pecah Rekor ⚡',
  ];
  String _selectedFeeling = 'Luar Biasa 🔥';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _fitPreviewMap() {
    if (widget.routePoints.length >= 2) {
      final bounds = LatLngBounds.fromPoints(widget.routePoints);
      _previewMapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28)),
      );
    } else if (widget.routePoints.isNotEmpty) {
      _previewMapController.move(widget.routePoints.first, 16.0);
    }
  }

  Future<void> _pickActivityPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _selectedPhoto = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat foto: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _saveAndPost() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      String? savedPhotoPath;
      if (_selectedPhoto != null) {
        savedPhotoPath = await _storageService.saveRunPhoto(_selectedPhoto!);
      }

      final now = DateTime.now();
      final newRun = RunModel(
        id: now.millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim().isEmpty ? widget.defaultTitle : _titleController.text.trim(),
        date: "${now.day}/${now.month}/${now.year}",
        createdAt: now,
        distanceInKm: widget.distanceInKm,
        durationInSeconds: widget.durationInSeconds,
        pace: widget.pace,
        steps: widget.steps,
        calories: widget.calories,
        elevationGainM: widget.elevationGainM,
        routePoints: widget.routePoints,
        trackPoints: widget.trackPoints,
        notes: _notesController.text.trim(),
        photoPath: savedPhotoPath,
        feeling: _selectedFeeling,
      );

      await _storageService.saveRun(newRun);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan aktivitas: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _confirmDiscard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Buang Rekaman Lari?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Data GPS dan statistik sesi ini tidak akan disimpan.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kembali', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, false);
            },
            child: const Text('Buang', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = widget.routePoints.isNotEmpty
        ? widget.routePoints.first
        : const LatLng(-6.9311, 107.7733);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSaving) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: _confirmDiscard,
          ),
          title: const Text(
            'Post Aktivitas',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _saveAndPost,
                child: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Simpan & Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                    decoration: const InputDecoration(
                      hintText: 'Judul lari (misal: Lari Pagi Keliling Unpad)',
                      hintStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.normal),
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Ceritakan pengalaman larimu hari ini... Cuaca, rute, atau target berikutnya?',
                      hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bagaimana Rasanya Lari Ini?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _feelings.map((feeling) {
                  final isSelected = _selectedFeeling == feeling;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFeeling = feeling),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryOrange : AppColors.cardDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? AppColors.primaryOrange : Colors.white12),
                      ),
                      child: Text(
                        feeling,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Foto Momen Lari (Opsional)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (_selectedPhoto != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      _selectedPhoto!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPhoto = null),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _buildPhotoButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Pilih dari Galeri',
                      onTap: () => _pickActivityPhoto(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPhotoButton(
                      icon: Icons.camera_alt_outlined,
                      label: 'Ambil Foto',
                      onTap: () => _pickActivityPhoto(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            const Text(
              'Trek Rute GPS & Statistik',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        mapController: _previewMapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: 15.5,
                          backgroundColor: AppColors.backgroundDark,
                          onMapReady: _fitPreviewMap,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                        ),
                        children: [
                          const DarkOsmTileLayer(),
                          if (widget.routePoints.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: widget.routePoints,
                                  strokeWidth: 4.5,
                                  color: AppColors.primaryOrange,
                                ),
                              ],
                            ),
                          if (widget.routePoints.isNotEmpty)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: widget.routePoints.first,
                                  width: 16,
                                  height: 16,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.accentGreen,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                                if (widget.routePoints.length >= 2)
                                  Marker(
                                    point: widget.routePoints.last,
                                    width: 16,
                                    height: 16,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCol('JARAK', '${widget.distanceInKm.toStringAsFixed(2)} km'),
                        _buildStatCol('WAKTU', AppFormatters.formatClockDuration(widget.durationInSeconds)),
                        _buildStatCol('PACE', '${widget.pace} /km'),
                        _buildStatCol('KALORI', '${widget.calories.toStringAsFixed(0)} kcal'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.45)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryOrange, size: 26),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
      ],
    );
  }
}
