import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/gpx_exporter.dart';
import '../../../core/widgets/dark_osm_tile_layer.dart';
import '../domain/run_model.dart';
import '../domain/runner_stats.dart';

class RunDetailScreen extends StatefulWidget {
  final RunModel run;

  const RunDetailScreen({super.key, required this.run});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  final MapController _mapController = MapController();
  final ProfileStorageService _profileService = ProfileStorageService();
  final RunStorageService _runStorageService = RunStorageService();
  final ImagePicker _picker = ImagePicker();

  late RunModel _run;
  bool _hasValidPhoto = false;
  bool _didModify = false;

  UserProfileData _profile = UserProfileData.defaultProfile;

  static const List<String> _feelings = [
    'Luar Biasa 🔥',
    'Santai & Segar 🌿',
    'Kuat & Stabil 💪',
    'Tanjakan Berat ⛰️',
    'Pecah Rekor ⚡',
  ];

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    _loadProfileAndPhoto();
  }

  Future<void> _loadProfileAndPhoto() async {
    final p = await _profileService.getProfile();
    final photoExists = _run.photoPath != null && await File(_run.photoPath!).exists();
    if (mounted) {
      setState(() {
        _profile = p;
        _hasValidPhoto = photoExists;
      });
    }
  }

  // --- KALKULASI TELEMETRI LANJUTAN ---
  double get _avgSpeedKmh {
    if (_run.durationInSeconds <= 0) return 0.0;
    final hours = _run.durationInSeconds / 3600.0;
    return _run.distanceInKm / hours;
  }

  int get _cadenceSpm {
    if (_run.durationInSeconds <= 0 || _run.steps <= 0) return 0;
    final minutes = _run.durationInSeconds / 60.0;
    return (_run.steps / minutes).round();
  }

  double get _avgStrideLengthM {
    if (_run.steps <= 0 || _run.distanceInKm <= 0) return 0.0;
    return (_run.distanceInKm * 1000.0) / _run.steps;
  }

  int get _paceSecondsPerKm {
    final parts = _run.pace.split(':');
    if (parts.length != 2) return 0;
    final m = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    return (m * 60) + s;
  }

  Map<String, dynamic> get _trainingZone {
    final paceSec = _paceSecondsPerKm;
    if (paceSec <= 0) {
      return {'label': 'CASUAL SESSION', 'color': AppColors.textSecondary, 'desc': 'Aktivitas ringan / pemanasan.'};
    }
    if (paceSec <= 270) {
      return {'label': 'ZONA 4 • THRESHOLD', 'color': Colors.redAccent, 'desc': 'Intensitas tinggi, meningkatkan kecepatan puncak & VO2 Max.'};
    }
    if (paceSec <= 345) {
      return {'label': 'ZONA 3 • TEMPO RUN', 'color': AppColors.primaryOrange, 'desc': 'Ritme cepat terkendali, melatih daya tahan laktat.'};
    }
    if (paceSec <= 435) {
      return {'label': 'ZONA 2 • AEROBIC BASE', 'color': AppColors.accentGreen, 'desc': 'Zona pembakaran lemak optimal & daya tahan kardiovaskular.'};
    }
    return {'label': 'ZONA 1 • EASY RECOVERY', 'color': AppColors.accentBlue, 'desc': 'Pemulihan aktif dengan detak jantung stabil.'};
  }

  void _fitRouteBounds() {
    final pts = _run.routePoints;
    if (pts.length >= 2) {
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(42)),
      );
    } else if (pts.isNotEmpty) {
      _mapController.move(pts.first, 16.5);
    }
  }

  void _copyShareSummary() {
    final elevText = _run.elevationGainM >= 1 ? '\n• Elevasi: +${_run.elevationGainM.round()} m' : '';
    final notesText = _run.notes.isNotEmpty ? '\nCatatan: ${_run.notes}' : '';
    final summary = '''
🏃‍♂️ ADVENTURE RUNNER — RINGKASAN LARI
Atlet: ${_profile.name}
Judul: ${_run.title} (${_run.date})
• Jarak: ${_run.distanceInKm.toStringAsFixed(2)} km
• Waktu: ${AppFormatters.formatClockDuration(_run.durationInSeconds)}
• Pace Rata-rata: ${_run.pace} /km
• Kalori: ${_run.calories.toStringAsFixed(0)} kcal
• Langkah: ${_run.steps} step$elevText$notesText
''';
    Clipboard.setData(ClipboardData(text: summary.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ringkasan aktivitas disalin ke clipboard! Siap ditempel ke WhatsApp/IG.'),
        backgroundColor: AppColors.cardElevated,
      ),
    );
  }

  Future<void> _exportGpx() async {
    try {
      final gpxFile = await _runStorageService.exportRunToGpxFile(_run);
      final gpxXml = GpxExporter.toGpxXml(_run);
      await Clipboard.setData(ClipboardData(text: gpxXml));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPX disimpan (${gpxFile.path.split(Platform.pathSeparator).last}) & disalin ke clipboard.'),
            backgroundColor: AppColors.cardElevated,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor GPX: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _showEditActivitySheet() async {
    final titleCtrl = TextEditingController(text: _run.title);
    final notesCtrl = TextEditingController(text: _run.notes);
    String selectedFeeling = _feelings.contains(_run.feeling) ? _run.feeling : _feelings.first;
    String? tempPhotoPath = _hasValidPhoto ? _run.photoPath : null;
    File? newlyPickedPhoto;
    bool clearPhoto = false;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Edit Aktivitas Lari',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Judul Aktivitas',
                    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.backgroundDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: 'Catatan / Cerita Lari',
                    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.backgroundDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Perasaan / Vibe', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _feelings.map((f) {
                      final isSelected = selectedFeeling == f;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedFeeling = f),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryOrange : AppColors.backgroundDark,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isSelected ? AppColors.primaryOrange : Colors.white12),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primaryOrange),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        try {
                          final picked = await _picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1080,
                            maxHeight: 1080,
                            imageQuality: 85,
                          );
                          if (picked != null) {
                            setSheetState(() {
                              newlyPickedPhoto = File(picked.path);
                              tempPhotoPath = picked.path;
                              clearPhoto = false;
                            });
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.photo_library_outlined, size: 16, color: AppColors.primaryOrange),
                      label: Text(
                        tempPhotoPath != null ? 'Ganti Foto' : 'Tambah Foto',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    if (tempPhotoPath != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          setSheetState(() {
                            newlyPickedPhoto = null;
                            tempPhotoPath = null;
                            clearPhoto = true;
                          });
                        },
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        label: const Text('Hapus Foto', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            final trimmedTitle = titleCtrl.text.trim();
                            if (trimmedTitle.isEmpty) return;

                            setSheetState(() => isSaving = true);
                            String? newSavedPhotoPath;
                            if (newlyPickedPhoto != null) {
                              newSavedPhotoPath = await _runStorageService.saveRunPhoto(newlyPickedPhoto!);
                            }

                            // Hapus file foto lama jika diganti atau dihapus
                            if ((clearPhoto || newSavedPhotoPath != null) && _run.photoPath != null) {
                              final oldFile = File(_run.photoPath!);
                              if (await oldFile.exists()) {
                                try {
                                  await oldFile.delete();
                                } catch (_) {}
                              }
                            }

                            final updated = _run.copyWith(
                              title: trimmedTitle,
                              notes: notesCtrl.text.trim(),
                              feeling: selectedFeeling,
                              photoPath: newSavedPhotoPath,
                              clearPhoto: clearPhoto,
                            );

                            await _runStorageService.updateRun(updated);
                            final validPhoto = updated.photoPath != null && await File(updated.photoPath!).exists();

                            if (mounted) {
                              setState(() {
                                _run = updated;
                                _hasValidPhoto = validPhoto;
                                _didModify = true;
                              });
                            }
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Perubahan aktivitas berhasil disimpan.'),
                                  backgroundColor: AppColors.cardElevated,
                                ),
                              );
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Simpan Perubahan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Aktivitas?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: const Text(
          'Aktivitas ini akan dihapus secara permanen dari riwayat Anda.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _runStorageService.deleteRun(_run.id);

              if (context.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aktivitas berhasil dihapus'),
                    backgroundColor: AppColors.cardElevated,
                  ),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _run.routePoints;
    final LatLng initialCenter = pts.isNotEmpty ? pts.first : const LatLng(-6.9311, 107.7733);
    final zone = _trainingZone;
    final splits = RunnerStats.calculateKmSplits(_run);
    final bool hasActualSplits = splits.isNotEmpty && splits.first.isActualTelemetry;
    final hasAvatar = _profile.avatarPath != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _didModify);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          title: Text(
            _run.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
          ),
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Edit Aktivitas',
              icon: const Icon(Icons.edit_outlined, color: Colors.white70),
              onPressed: _showEditActivitySheet,
            ),
            IconButton(
              tooltip: 'Salin Ringkasan Lari',
              icon: const Icon(Icons.share_outlined, color: AppColors.primaryOrange),
              onPressed: _copyShareSummary,
            ),
            IconButton(
              tooltip: 'Hapus Aktivitas',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // 1. PETA RUTE AUTO-FIT BOUNDS + LEGEND START/FINISH
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 16.0,
                      backgroundColor: AppColors.backgroundDark,
                      onMapReady: _fitRouteBounds,
                    ),
                    children: [
                      const DarkOsmTileLayer(),
                      if (pts.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: pts,
                              strokeWidth: 5.5,
                              color: AppColors.primaryOrange,
                            ),
                          ],
                        ),
                      if (pts.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: pts.first,
                              width: 28,
                              height: 28,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                                child: const Center(
                                  child: Text('S', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
                                ),
                              ),
                            ),
                            if (pts.length >= 2)
                              Marker(
                                point: pts.last,
                                width: 28,
                                height: 28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                  ),
                                  child: const Center(
                                    child: Text('F', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(radius: 5, backgroundColor: AppColors.accentGreen),
                        const SizedBox(width: 5),
                        const Text('Start', style: TextStyle(color: Colors.white, fontSize: 11)),
                        const SizedBox(width: 10),
                        const CircleAvatar(radius: 5, backgroundColor: Colors.redAccent),
                        const SizedBox(width: 5),
                        const Text('Finish', style: TextStyle(color: Colors.white, fontSize: 11)),
                        const SizedBox(width: 8),
                        Text(
                          '• ${pts.length} titik GPS',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  right: 14,
                  top: 10,
                  child: OsmAttributionBadge(),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'btn_detail_fit_route',
                    backgroundColor: AppColors.cardDark,
                    onPressed: _fitRouteBounds,
                    child: const Icon(Icons.crop_free, color: AppColors.primaryOrange, size: 20),
                  ),
                ),
              ],
            ),

            // 2. HEADER ATLET + ZONA INTENSITAS + FEELING + NOTES + FOTO
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.cardElevated,
                        backgroundImage: hasAvatar ? FileImage(File(_profile.avatarPath!)) : null,
                        child: !hasAvatar ? const Icon(Icons.person, color: Colors.white70, size: 20) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profile.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              '${_run.date} • ${_profile.city}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: (zone['color'] as Color).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (zone['color'] as Color).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          zone['label'] as String,
                          style: TextStyle(
                            color: zone['color'] as Color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _run.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  if (_run.feeling.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _run.feeling,
                        style: const TextStyle(
                          color: AppColors.primaryOrangeLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    zone['desc'] as String,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  if (_run.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        _run.notes,
                        style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ],
                  if (_hasValidPhoto && _run.photoPath != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(_run.photoPath!),
                        width: double.infinity,
                        height: 230,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // 3. GRID METRIK TELEMETRI UTAMA
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildTelemetryTile('JARAK TEMPUH', '${_run.distanceInKm.toStringAsFixed(2)} km', AppColors.primaryOrange),
                            _buildTelemetryTile('AVG PACE', '${_run.pace} /km', Colors.white),
                          ],
                        ),
                        const Divider(height: 24, color: Colors.white10),
                        Row(
                          children: [
                            _buildTelemetryTile('DURASI AKTIF', AppFormatters.formatClockDuration(_run.durationInSeconds), AppColors.accentBlue),
                            _buildTelemetryTile('KECEPATAN', '${_avgSpeedKmh.toStringAsFixed(1)} km/j', Colors.white),
                          ],
                        ),
                        const Divider(height: 24, color: Colors.white10),
                        Row(
                          children: [
                            _buildTelemetryTile('KALORI TERBAKAR', '${_run.calories.toStringAsFixed(0)} kcal', AppColors.accentGreen),
                            _buildTelemetryTile('TOTAL LANGKAH', '${_run.steps} step', Colors.white),
                          ],
                        ),
                        if (_cadenceSpm > 0 || _run.elevationGainM >= 1) ...[
                          const Divider(height: 24, color: Colors.white10),
                          Row(
                            children: [
                              if (_cadenceSpm > 0)
                                _buildTelemetryTile('KADENSI', '$_cadenceSpm spm', Colors.amber)
                              else
                                _buildTelemetryTile('ELEVASI GAIN', '+${_run.elevationGainM.round()} m', AppColors.accentGreen),
                              if (_cadenceSpm > 0 && _run.elevationGainM >= 1)
                                _buildTelemetryTile('ELEVASI GAIN', '+${_run.elevationGainM.round()} m', AppColors.accentGreen)
                              else
                                _buildTelemetryTile('PANJANG LANGKAH', '${_avgStrideLengthM.toStringAsFixed(2)} m', Colors.white),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 4. ANALISIS SPLIT PER KILOMETER
                  if (splits.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Analisis Split per Kilometer',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (hasActualSplits ? AppColors.accentGreen : AppColors.textSecondary).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hasActualSplits ? 'Telemetri GPS' : 'Rata-rata',
                            style: TextStyle(
                              color: hasActualSplits ? AppColors.accentGreen : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              SizedBox(width: 45, child: Text('KM', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              SizedBox(width: 65, child: Text('PACE', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              Expanded(child: Text('INTENSITAS KECEPATAN', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          ...splits.map((s) {
                            final barRatio = (s.speedKmh / 16.0).clamp(0.15, 1.0);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 45,
                                    child: Text(
                                      s.distanceKm < 1.0 ? s.distanceKm.toStringAsFixed(1) : '${s.kmIndex}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 65,
                                    child: Text(
                                      s.paceStr,
                                      style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: barRatio,
                                        minHeight: 10,
                                        backgroundColor: Colors.white10,
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 5. TOMBOL BAGIKAN RINGKASAN & EKSPOR GPX
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primaryOrange),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _copyShareSummary,
                            icon: const Icon(Icons.copy_all, color: AppColors.primaryOrange, size: 19),
                            label: const Text(
                              'Salin Ringkasan',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.accentBlue),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _exportGpx,
                            icon: const Icon(Icons.download_outlined, color: AppColors.accentBlue, size: 19),
                            label: const Text(
                              'Ekspor GPX',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryTile(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: valueColor),
          ),
        ],
      ),
    );
  }
}
