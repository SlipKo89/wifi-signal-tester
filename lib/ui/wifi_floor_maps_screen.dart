import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import '../services/floor_plan_image_picker.dart';
import '../state/monitor_controller.dart';
import '../wifi_map/wifi_floor_plan.dart';
import '../wifi_map/wifi_floor_plan_bundle.dart';
import '../wifi_map/wifi_floor_plan_store.dart';
import 'wifi_floor_plan_editor.dart';
import 'widgets/app_safe_area.dart';

class WifiFloorMapsScreen extends StatefulWidget {
  final WifiFloorPlanStore? store;
  final FloorPlanImagePicker? imagePicker;
  final FloorPlanProjectPicker? projectPicker;

  const WifiFloorMapsScreen({
    super.key,
    this.store,
    this.imagePicker,
    this.projectPicker,
  });

  @override
  State<WifiFloorMapsScreen> createState() => _WifiFloorMapsScreenState();
}

class _WifiFloorMapsScreenState extends State<WifiFloorMapsScreen> {
  late final WifiFloorPlanStore _store;
  late final FloorPlanImagePicker _imagePicker;
  late final FloorPlanProjectPicker _projectPicker;
  List<WifiFloorPlan> _plans = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? WifiFloorPlanStore();
    final nativePicker = NativeFloorPlanImagePicker();
    _imagePicker = widget.imagePicker ?? nativePicker;
    _projectPicker = widget.projectPicker ?? nativePicker;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final plans = await _store.loadAll();
      if (mounted) setState(() => _plans = plans);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create({required bool importImage}) async {
    final l = context.read<SettingsController>().l;
    PickedFloorPlanImage? image;
    if (importImage) {
      try {
        image = await _imagePicker.pick();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t(
            'Could not read the selected image: $error',
            'Не удалось прочитать выбранное изображение: $error',
          )),
        ));
        return;
      }
      if (image == null || !mounted) return;
    }

    final draft = await showDialog<_PlanDraft>(
      context: context,
      builder: (_) => _PlanDialog(importedFileName: image?.name),
    );
    if (draft == null || !mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'map-${DateTime.now().microsecondsSinceEpoch}';
    var plan = WifiFloorPlan(
      id: id,
      name: draft.name,
      widthMeters: draft.width,
      heightMeters: draft.height,
      cellSizeMeters: draft.cell,
      createdAtMs: now,
      updatedAtMs: now,
    );
    try {
      if (image != null) {
        final imagePath = await _store.saveBackground(
          planId: id,
          bytes: image.bytes,
          extension: p.extension(image.name),
        );
        plan = plan.copyWith(backgroundImagePath: imagePath);
      }
      await _store.save(plan);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WifiFloorPlanEditor(
            plan: plan,
            store: _store,
            monitor: context.read<MonitorController>(),
          ),
        ),
      );
      await _load();
    } catch (error) {
      try {
        await _store.deleteOwnedBackground(plan.backgroundImagePath);
      } catch (_) {
        // Preserve the original create/save failure for the user.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Could not create the map: $error',
          'Не удалось создать карту: $error',
        )),
      ));
    }
  }

  Future<void> _open(WifiFloorPlan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WifiFloorPlanEditor(
          plan: plan,
          store: _store,
          monitor: context.read<MonitorController>(),
        ),
      ),
    );
    await _load();
  }

  Future<void> _export(WifiFloorPlan plan) async {
    final l = context.read<SettingsController>().l;
    final options = await showDialog<_ExportOptions>(
      context: context,
      builder: (_) => _ExportDialog(plan: plan),
    );
    if (options == null || !mounted) return;
    try {
      final file = await WifiFloorPlanBundle.writeTemporary(
        plan,
        includeBackground: options.background,
        includeMeasurements: options.measurements,
        includeGps: options.gps,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: WifiFloorPlanBundle.mimeType)],
        subject: '${l.t('Wi-Fi floor map', 'Карта Wi-Fi')}: ${plan.name}',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Could not export the map: $error',
          'Не удалось экспортировать карту: $error',
        )),
      ));
    }
  }

  Future<void> _importProject() async {
    final l = context.read<SettingsController>().l;
    try {
      final selected = await _projectPicker.pickProject();
      if (selected == null || !mounted) return;
      final bundle = WifiFloorPlanBundle.importBytes(selected.bytes);
      final existing =
          _plans.where((plan) => plan.id == bundle.plan.id).toList();
      var targetId = bundle.plan.id;
      var targetName = bundle.plan.name;
      WifiFloorPlan? replaced;
      if (existing.isNotEmpty) {
        final action = await showDialog<_ImportAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Map already exists', 'Карта уже существует')),
            content: Text(l.t(
              'Replace “${existing.single.name}” with the imported project, or create a separate copy?',
              'Заменить «${existing.single.name}» импортированным проектом или создать отдельную копию?',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _ImportAction.copy),
                child: Text(l.t('Create copy', 'Создать копию')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _ImportAction.replace),
                child: Text(l.t('Replace', 'Заменить')),
              ),
            ],
          ),
        );
        if (action == null || !mounted) return;
        if (action == _ImportAction.copy) {
          targetId = 'map-${DateTime.now().microsecondsSinceEpoch}';
          targetName =
              l.t('${bundle.plan.name} copy', '${bundle.plan.name} — копия');
        } else {
          replaced = existing.single;
        }
      }

      String? newBackground;
      var persisted = false;
      try {
        if (bundle.backgroundBytes != null &&
            bundle.backgroundExtension != null) {
          newBackground = await _store.saveBackground(
            planId: '$targetId-import-${DateTime.now().microsecondsSinceEpoch}',
            bytes: bundle.backgroundBytes!,
            extension: bundle.backgroundExtension!,
          );
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final imported = WifiFloorPlan(
          id: targetId,
          name: targetName,
          widthMeters: bundle.plan.widthMeters,
          heightMeters: bundle.plan.heightMeters,
          cellSizeMeters: bundle.plan.cellSizeMeters,
          backgroundImagePath: newBackground,
          backgroundOpacity: bundle.plan.backgroundOpacity,
          captureGps: bundle.plan.captureGps,
          walls: bundle.plan.walls,
          surveys: bundle.plan.surveys,
          measurements: bundle.plan.measurements,
          createdAtMs: replaced?.createdAtMs ?? now,
          updatedAtMs: now,
        );
        await _store.save(imported);
        persisted = true;
        if (replaced?.backgroundImagePath != newBackground) {
          try {
            await _store.deleteOwnedBackground(replaced?.backgroundImagePath);
          } catch (_) {
            // The newly imported project is already valid; an obsolete
            // app-owned image can be cleaned up on a later maintenance pass.
          }
        }
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t(
            'Map “$targetName” imported',
            'Карта «$targetName» импортирована',
          )),
        ));
      } catch (_) {
        if (!persisted) await _store.deleteOwnedBackground(newBackground);
        rethrow;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Could not import the project: $error',
          'Не удалось импортировать проект: $error',
        )),
      ));
    }
  }

  Future<void> _delete(WifiFloorPlan plan) async {
    final l = context.read<SettingsController>().l;
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.t('Delete map?', 'Удалить карту?')),
            content: Text(l.t(
              'The plan, traced walls and its app-owned image copy will be deleted.',
              'План, обведённые стены и сохранённая приложением копия изображения будут удалены.',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.t('Cancel', 'Отмена')),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.t('Delete', 'Удалить')),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    try {
      await _store.delete(plan.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t(
          'Could not delete the map: $error',
          'Не удалось удалить карту: $error',
        )),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Wi-Fi floor maps', 'Карты Wi-Fi')),
        actions: [
          PopupMenuButton<String>(
            tooltip: l.t('Create map', 'Создать карту'),
            icon: const Icon(Icons.add),
            onSelected: (value) {
              if (value == 'project') {
                _importProject();
              } else {
                _create(importImage: value == 'image');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'grid',
                child: ListTile(
                  leading: const Icon(Icons.grid_on_outlined),
                  title: Text(l.t('Draw on a grid', 'Нарисовать на сетке')),
                ),
              ),
              PopupMenuItem(
                value: 'image',
                child: ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title:
                      Text(l.t('Import an image', 'Импортировать изображение')),
                ),
              ),
              PopupMenuItem(
                value: 'project',
                child: ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(l.t(
                    'Import .wifimap project',
                    'Импортировать проект .wifimap',
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AppSafeArea(child: _body(l)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(importImage: false),
        icon: const Icon(Icons.grid_on_outlined),
        label: Text(l.t('New map', 'Новая карта')),
      ),
    );
  }

  Widget _body(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(l.t('Could not load maps.', 'Не удалось загрузить карты.')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l.t('Retry', 'Повторить')),
              ),
            ],
          ),
        ),
      );
    }
    if (_plans.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 120),
        children: [
          const Icon(Icons.map_outlined, size: 64, color: Color(0xFF7D8590)),
          const SizedBox(height: 18),
          Text(
            l.t('Create the first floor map', 'Создай первую карту помещения'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            l.t(
              'Draw walls on a scaled grid or trace a photo/plan, then create survey sessions and place two-sided measurement points.',
              'Рисуй стены на сетке или обведи фото/план, затем создавай сессии обследования и ставь точки двусторонних замеров.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B949E), height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _create(importImage: true),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
                l.t('Import plan or photo', 'Импортировать план или фото')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _create(importImage: false),
            icon: const Icon(Icons.grid_on_outlined),
            label: Text(l.t('Start with a grid', 'Начать с сетки')),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final plan = _plans[index];
          final imagePath = plan.backgroundImagePath;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: SizedBox(
                width: 64,
                height: 64,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFF1C2530)),
                  child: imagePath != null && File(imagePath).existsSync()
                      ? Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                          cacheHeight: 192,
                        )
                      : const Icon(Icons.grid_on_outlined),
                ),
              ),
              title:
                  Text(plan.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_number(plan.widthMeters)} × ${_number(plan.heightMeters)} m · '
                '${_number(plan.cellSizeMeters)} m · ${plan.walls.length} '
                '${l.t('objects', 'объектов')} · ${plan.surveys.length} '
                '${l.t('sessions', 'сессий')} · ${plan.measurements.length} '
                '${l.t('points', 'точек')}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') _delete(plan);
                  if (value == 'export') _export(plan);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'export',
                    child: Text(l.t('Export .wifimap', 'Экспорт .wifimap')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l.t('Delete', 'Удалить')),
                  ),
                ],
              ),
              onTap: () => _open(plan),
            ),
          );
        },
      ),
    );
  }
}

enum _ImportAction { replace, copy }

class _ExportOptions {
  final bool background;
  final bool measurements;
  final bool gps;

  const _ExportOptions({
    required this.background,
    required this.measurements,
    required this.gps,
  });
}

class _ExportDialog extends StatefulWidget {
  final WifiFloorPlan plan;

  const _ExportDialog({required this.plan});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late bool _background;
  bool _measurements = true;
  bool _gps = false;

  bool get _hasGps =>
      widget.plan.measurements.any((sample) => sample.geo != null);

  @override
  void initState() {
    super.initState();
    _background = widget.plan.backgroundImagePath != null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return AlertDialog(
      title: Text(l.t('Export floor map', 'Экспорт карты')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _background,
              onChanged: widget.plan.backgroundImagePath == null
                  ? null
                  : (value) => setState(() => _background = value),
              title: Text(l.t('Include plan image', 'Включить подложку')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _measurements,
              onChanged: (value) => setState(() {
                _measurements = value;
                if (!value) _gps = false;
              }),
              title: Text(l.t('Include measurements', 'Включить замеры')),
              subtitle: Text(l.t(
                '${widget.plan.measurements.length} points; signal values and AP names',
                '${widget.plan.measurements.length} точек; значения сигнала и имена AP',
              )),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _gps,
              onChanged: !_measurements || !_hasGps
                  ? null
                  : (value) => setState(() => _gps = value),
              title: Text(l.t('Include GPS context', 'Включить GPS-контекст')),
              subtitle: Text(l.t(
                'Off by default because coordinates are sensitive',
                'По умолчанию выключено: координаты чувствительны',
              )),
            ),
            const SizedBox(height: 8),
            Text(
              l.t(
                'Router passwords, API tokens and connection profiles are never included.',
                'Пароли роутеров, API-токены и профили подключений не экспортируются.',
              ),
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Cancel', 'Отмена')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _ExportOptions(
              background: _background,
              measurements: _measurements,
              gps: _gps,
            ),
          ),
          icon: const Icon(Icons.ios_share),
          label: Text(l.t('Export', 'Экспортировать')),
        ),
      ],
    );
  }
}

class _PlanDraft {
  final String name;
  final double width;
  final double height;
  final double cell;

  const _PlanDraft(this.name, this.width, this.height, this.cell);
}

class _PlanDialog extends StatefulWidget {
  final String? importedFileName;

  const _PlanDialog({this.importedFileName});

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _width = TextEditingController(text: '12');
  final _height = TextEditingController(text: '8');
  final _cell = TextEditingController(text: '0.5');

  @override
  void initState() {
    super.initState();
    final fileName = widget.importedFileName;
    _name = TextEditingController(
      text: fileName == null ? '' : p.basenameWithoutExtension(fileName),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _cell.dispose();
    super.dispose();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    String? dimension(String? text) {
      final value = _parse(text ?? '');
      if (value == null || !value.isFinite || value <= 0 || value > 500) {
        return l.t('Enter 0–500 m', 'Укажи значение 0–500 м');
      }
      return null;
    }

    String? cell(String? text) {
      final value = _parse(text ?? '');
      if (value == null || !value.isFinite || value < 0.1 || value > 10) {
        return l.t('Enter 0.1–10 m', 'Укажи значение 0,1–10 м');
      }
      return null;
    }

    return AlertDialog(
      title: Text(l.t('Map parameters', 'Параметры карты')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration:
                      InputDecoration(labelText: l.t('Name', 'Название')),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l.t('Enter a name', 'Укажи название')
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _width,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: l.t('Width, m', 'Ширина, м')),
                        validator: dimension,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: l.t('Height, m', 'Высота, м')),
                        validator: dimension,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cell,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l.t('Grid cell, m', 'Сторона клетки, м'),
                    helperText: l.t(
                      'Walls snap to grid intersections',
                      'Стены привязываются к узлам сетки',
                    ),
                  ),
                  validator: cell,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Cancel', 'Отмена')),
        ),
        FilledButton(
          key: const Key('create-floor-map'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PlanDraft(
                _name.text.trim(),
                _parse(_width.text)!,
                _parse(_height.text)!,
                _parse(_cell.text)!,
              ),
            );
          },
          child: Text(l.t('Create', 'Создать')),
        ),
      ],
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
