// FILE: lib/main.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_screen.dart';
import 'image_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FixMyRoadApp());
}

class FixMyRoadApp extends StatelessWidget {
  const FixMyRoadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fix My Road',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.indigo,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _homeKey = GlobalKey();
  final _howToKey = GlobalKey();
  final _reportKey = GlobalKey();
  final _bottomKey = GlobalKey();
  String? _demoImageName;
  String? _videoName;
  _VideoReport? _latestReport;
  final List<_VideoReport> _history = [];
  late final AnimationController _bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  late final AnimationController _dashCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final AnimationController _glintCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() {
    _scrollController.dispose();
    _bgCtrl.dispose();
    _dashCtrl.dispose();
    _glintCtrl.dispose();
    super.dispose();
  }

  void _jumpTo(GlobalKey key) {
    _ensureVisible(key, curve: Curves.easeInOutCubic, duration: const Duration(milliseconds: 700));
  }

  Future<void> _ensureVisible(GlobalKey key, {Curve curve = Curves.ease, Duration? duration}) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: duration ?? const Duration(milliseconds: 400),
      curve: curve,
      alignment: 0.06,
    );
  }

  // --- THIS IS THE NEW, WORKING "DEMO" BUTTON LOGIC ---
  Future<void> _pickDemoImage() async {
    // 1. Ask for Photo permission
    var status = await Permission.photos.request();

    if (status.isGranted) {
      // 2. If permission is granted, open the gallery
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        // 3. We got an image!
        setState(() {
          _demoImageName = image.name.split('/').last; // Show the file name
        });
        if (mounted) {
          // 4. Open the new test screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageTestScreen(imagePath: image.path),
            ),
          );
        }
      } else {
        print("Image selection cancelled.");
      }
    } else {
      // 5. If permission is denied
      print("Photo Gallery permission was denied.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permission to access photos is required for this demo.')),
        );
      }
    }
  }

  // --- THIS IS THE NEW, WORKING "LIVE" BUTTON LOGIC ---
  Future<void> _startLiveDetection() async {
    // Ask for both Camera and Location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
    ].request();

    // Check if both are granted
    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.locationWhenInUse]!.isGranted) {
      // If yes, open the camera_screen.dart file
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CameraScreen()),
        );
      }
    } else {
      // Show an error if permissions are denied
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Camera & Location permissions are required for live detection.')),
        );
      }
    }
  }

  // (All the other functions from your friend's code are identical)
  Future<_VideoReport> _simulateReport({required String videoName}) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final rng = Random();
    int frames = rng.nextInt(500) + 600;
    int detections = rng.nextInt(12) + 7;
    final double calcHigh = detections * (0.28 + rng.nextDouble() * 0.18);
    final int roundedHigh = calcHigh.round();
    int high = max(1, roundedHigh);
    final double calcMedium = detections * (0.38 + rng.nextDouble() * 0.22);
    final int roundedMedium = calcMedium.round();
    int medium = max(1, roundedMedium);
    int low = max(0, detections - high - medium);
    double confAvg = (0.74 + rng.nextDouble() * 0.22);
    final hotSpots = List.generate(
      min(3, max(1, detections ~/ 4)),
      (_) => _HotSpot(
        lat: 12.90 + rng.nextDouble() * 0.25,
        lng: 77.50 + rng.nextDouble() * 0.25,
        severity: ['High', 'Medium', 'Low'][rng.nextInt(3)],
      ),
    );
    return _VideoReport(
      videoName: videoName,
      frames: frames,
      totalDetections: detections,
      high: high,
      medium: medium,
      low: low,
      avgConfidence: confAvg,
      generatedAt: DateTime.now(),
      hotSpots: hotSpots,
    );
  }

  void _showHistory() {
    if (_history.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => const _InfoDialog(
          title: 'History',
          body: 'No reports yet. Upload a video to generate your first report.',
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView.separated(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: _history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ReportCard(report: _history[i], compact: true),
        ),
      ),
    );
  }

  void _openFeedback() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FeedbackSheet(),
    );
  }

  PopupMenuButton<String> _menu() {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      onSelected: (v) {
        switch (v) {
          case 'home':
            _jumpTo(_homeKey);
            break;
          case 'how':
            _jumpTo(_howToKey);
            break;
          case 'history':
            _showHistory();
            break;
          case 'about':
            showDialog(
              context: context,
              builder: (_) => const _InfoDialog(
                title: 'About Us',
                body:
                    'Fix My Road uses computer vision to detect potholes from road videos and generate actionable reports for faster maintenance.',
              ),
            );
            break;
          case 'contact':
            showDialog(
              context: context,
              builder: (_) => const _InfoDialog(
                title: 'Contact Us',
                body:
                    'Email: support@fixmyroad.org\nPhone: +91 98765 43210\nAddress: 123 Civic Tech Park, Bengaluru',
              ),
            );
            break;
          case 'feedback':
            _openFeedback();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'home', child: Text('Home')),
        PopupMenuItem(value: 'how', child: Text('How to Use')),
        PopupMenuItem(value: 'history', child: Text('History')),
        PopupMenuItem(value: 'about', child: Text('About Us')),
        PopupMenuItem(value: 'contact', child: Text('Contact Us')),
        PopupMenuItem(value: 'feedback', child: Text('Feedback')),
      ],
      icon: const Icon(Icons.menu),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fix My Road'),
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {},
            child: Row(
              children: [
                Image.asset(
                  'assets/logo.png', // <-- Your friend's logo path
                  height: 40,
                  width: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
        actions: [
          _menu(),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (_, __) {
          final t = _bgCtrl.value;
          final colors = [
            HSLColor.fromAHSL(1, (t * 360) % 360, 0.68, 0.58).toColor(),
            HSLColor.fromAHSL(1, (t * 360 + 120) % 360, 0.68, 0.62).toColor(),
            HSLColor.fromAHSL(1, (t * 360 + 240) % 360, 0.68, 0.66).toColor(),
          ];
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: const Alignment(-0.8, -1.0),
                end: const Alignment(0.8, 1.0),
              ),
            ),
            child: Stack(
              children: [
                _AnimatedBlob(
                  controller: _bgCtrl,
                  size: 220,
                  dx: -0.6,
                  dy: -0.7,
                  color: Colors.white.withOpacity(0.10),
                ),
                _AnimatedBlob(
                  controller: _bgCtrl,
                  size: 260,
                  dx: 0.7,
                  dy: -0.4,
                  color: Colors.white.withOpacity(0.08),
                ),
                _AnimatedBlob(
                  controller: _bgCtrl,
                  size: 300,
                  dx: -0.5,
                  dy: 0.65,
                  color: Colors.white.withOpacity(0.08),
                ),
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _heroSection(context, key: _homeKey)),
                    SliverToBoxAdapter(child: _actionsSection(context)),
                    SliverToBoxAdapter(child: _reportSection(context, key: _reportKey)),
                    SliverToBoxAdapter(child: _howToUseSection(context, key: _howToKey)),
                    SliverToBoxAdapter(child: _bottomSection(context, key: _bottomKey)),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openFeedback,
        icon: const Icon(Icons.rate_review),
        label: const Text('Feedback'),
        backgroundColor: cs.tertiary,
        foregroundColor: cs.onTertiary,
      ),
    );
  }

  Widget _heroSection(BuildContext context, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: _FrostedCard(
        borderRadius: 28,
        glassy: true,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: LayoutBuilder(
            builder: (_, c) {
              final isNarrow = c.maxWidth < 680;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(
                      colors: [cs.onPrimaryContainer, cs.primary, cs.secondary, cs.tertiary],
                    ).createShader(r),
                    child: const Text(
                      'Fix My Road',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 0.2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: isNarrow ? 170 : 210,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _glintCtrl,
                          builder: (_, __) {
                            final v = _glintCtrl.value;
                            return Transform.rotate(
                              angle: 0.3,
                              child: Opacity(
                                opacity: 0.25 + 0.25 * sin(v * pi * 2),
                                child: Container(
                                  width: isNarrow ? 180 : 220,
                                  height: isNarrow ? 120 : 150,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.10),
                                        Colors.white.withOpacity(0.30),
                                        Colors.white.withOpacity(0.10),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _dashCtrl,
                            builder: (_, __) => CustomPaint(
                              size: Size(isNarrow ? 260 : 320, isNarrow ? 140 : 180),
                              painter: _RoadPainter(dashOffset: _dashCtrl.value),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _actionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          _FrostedCard(
            glassy: true,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Text('Get Started', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.primary)),
                const SizedBox(height: 6),
                Text(
                  'Use a demo image or upload a road video for live detection.\n'
                  'We will generate a clear report with hotspots & severity.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.photo_library,
                        label: 'Demo',
                        subtitle: _demoImageName == null ? 'Upload image' : 'Selected: $_demoImageName',
                        onPressed: _pickDemoImage,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.videocam,
                        label: 'Live Detection',
                        subtitle: 'Start live dashcam',
                        onPressed: _startLiveDetection, 
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection(BuildContext context, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutBack,
            child: (_latestReport == null)
                ? _emptyReportPlaceholder(context)
                : _ReportCard(report: _latestReport!),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _emptyReportPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _FrostedCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.analytics_outlined, color: cs.onPrimaryContainer),
        ),
        title: const Text('No Report Yet'),
        subtitle: const Text('Start Live Detection to generate an AI report.'),
      ),
    );
  }

  Widget _howToUseSection(BuildContext context, {Key? key}) {
    final steps = [
      ('Start', 'Tap "Start Live Detection" and grant camera & location permissions.'),
      ('Mount', 'Mount your phone securely on your car\'s dashboard.'),
      ('Drive', 'Drive normally. The app will automatically detect potholes in real-time.'),
      ('Review', 'Detections are automatically sent to our system to generate reports.'),
    ];
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: _FrostedCard(
        glassy: true,
        child: ExpansionTile(
          initiallyExpanded: true,
          title: const Text('How to Use'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final s in steps)
              ListTile(
                leading: Icon(_iconForStep(s.$1)),
                title: Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(s.$2),
                dense: true,
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForStep(String step) {
    switch (step) {
      case 'Start':
        return Icons.play_circle_fill;
      case 'Mount':
        return Icons.phone_android;
      case 'Drive':
        return Icons.directions_car;
      case 'Review':
        return Icons.fact_check;
      default:
        return Icons.insights;
    }
  }

  Widget _bottomSection(BuildContext context, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: _FrostedCard(
        glassy: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stay Connected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.primary)),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _SocialChip(icon: Icons.public, label: 'fixmyroad.org'),
                _SocialChip(icon: Icons.photo_camera, label: '@fixmyroad'),
                _SocialChip(icon: Icons.facebook, label: 'facebook.com/fixmyroad'),
                _SocialChip(icon: Icons.share, label: 'Share with community'),
              ],
            ),
            const SizedBox(height: 14),
            Text('Contact', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
            const SizedBox(height: 6),
            const Text('Email: support@fixmyroad.org • Phone: +91 98765 43210'),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _openFeedback,
              icon: const Icon(Icons.rate_review),
              label: const Text('Send Feedback'),
            ),
          ],
        ),
      ),
    );
  }
}

// (All helper classes _HotSpot, _VideoReport, _FrostedCard, etc. are IDENTICAL)

class _HotSpot {
  final double lat;
  final double lng;
  final String severity;
  _HotSpot({required this.lat, required this.lng, required this.severity});
}

class _VideoReport {
  final String videoName;
  final int frames;
  final int totalDetections;
  final int high;
  final int medium;
  final int low;
  final double avgConfidence;
  final DateTime generatedAt;
  final List<_HotSpot> hotSpots;
  _VideoReport({
    required this.videoName,
    required this.frames,
    required this.totalDetections,
    required this.high,
    required this.medium,
    required this.low,
    required this.avgConfidence,
    required this.generatedAt,
    required this.hotSpots,
  });
}


class _FrostedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool glassy;
  const _FrostedCard({
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.glassy = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = glassy ? Colors.white.withOpacity(0.28) : cs.surface.withOpacity(0.72);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onPressed;
  final LinearGradient gradient;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.gradient,
    this.subtitle,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: _hover ? 1.02 : 1.0,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ScaleTransition(
                          scale: Tween(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
                          child: const CircleAvatar(backgroundColor: Colors.white24, radius: 18),
                        ),
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.circle, size: 0, color: Colors.transparent),
                        ),
                        const SizedBox.shrink(),
                        const SizedBox(),
                        const SizedBox(),
                        const SizedBox(),
                        Icon(widget.icon, color: Colors.white),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.label,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final _VideoReport report;
  final bool compact;
  const _ReportCard({required this.report, this.compact = false});

  Color _sevColor(String s) {
    switch (s) {
      case 'High':
        return Colors.red.shade600;
      case 'Medium':
        return Colors.orange.shade700;
      default:
        return Colors.green.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time =
        '${report.generatedAt.year}-${_pad(report.generatedAt.month)}-${_pad(report.generatedAt.day)}  ${_pad(report.generatedAt.hour)}:${_pad(report.generatedAt.minute)}';

    return _FrostedCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      glassy: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.summarize, color: cs.onPrimaryContainer),
            ),
            title: Text('AI Report — ${report.videoName}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('Generated: $time'),
            trailing: Chip(
              label: Text('${report.totalDetections} potholes'),
              avatar: const Icon(Icons.warning_amber_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(context, 'Frames', '${report.frames}', Icons.movie_filter, color: cs.primary),
              _metric(context, 'High', '${report.high}', Icons.priority_high, color: _sevColor('High')),
              _metric(context, 'Medium', '${report.medium}', Icons.report, color: _sevColor('Medium')),
              _metric(context, 'Low', '${report.low}', Icons.info, color: _sevColor('Low')),
              _metric(context, 'Avg Confidence', '${(report.avgConfidence * 100).toStringAsFixed(1)}%', Icons.analytics,
                  color: cs.tertiary),
            ],
          ),
          const SizedBox(height: 12),
          if (!compact) ...[
            Text('Hotspots', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.primary)),
            const SizedBox(height: 6),
            if (report.hotSpots.isEmpty)
              const Text('No concentrated hotspots found.')
            else
              Column(
                children: [
                  for (final h in report.hotSpots)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.location_on, color: _sevColor(h.severity)),
                      title: Text('Lat: ${h.lat.toStringAsFixed(5)}, Lng: ${h.lng.toStringAsFixed(5)}'),
                      subtitle: Text('Severity: ${h.severity}'),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, IconData icon, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: cs.onSurface)),
        ],
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _InfoDialog extends StatelessWidget {
  final String title;
  final String body;
  const _InfoDialog({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: cs.primary)),
        ),
      ],
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Thanks for your feedback!')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Share your feedback', style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Tell us what worked well and what can be improved…',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 6) ? 'Please enter at least 6 characters' : null,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBlob extends StatelessWidget {
  final AnimationController controller;
  final double size;
  final double dx;
  final double dy;
  final Color color;
  const _AnimatedBlob({
    required this.controller,
    required this.size,
    required this.dx,
    required this.dy,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final w = MediaQuery.of(context).size.width;
        final h = MediaQuery.of(context).size.height;
        final t = controller.value;
        final x = (w / 2) + dx * w * 0.45 + sin(t * 2 * pi) * 20;
        final y = (h / 2) + dy * h * 0.45 + cos(t * 2 * pi) * 20;
        return Positioned(
          left: x - size / 2,
          top: y - size / 2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 60, spreadRadius: 10)],
            ),
          ),
        );
      },
    );
  }
}

class _RoadPainter extends CustomPainter {
  final double dashOffset;
  _RoadPainter({required this.dashOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF252A34), const Color(0xFF3B3F4C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final topWidth = size.width * 0.35;
    final bottomWidth = size.width * 0.9;
    final roadPath = Path()
      ..moveTo((size.width - topWidth) / 2, 0)
      ..lineTo((size.width + topWidth) / 2, 0)
      ..lineTo((size.width + bottomWidth) / 2, size.height)
      ..lineTo((size.width - bottomWidth) / 2, size.height)
      ..close();

    canvas.drawPath(roadPath, roadPaint);

    final edgePaint = Paint()
      ..color = const Color(0xFF9AA0A6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(roadPath, edgePaint);

    final centerPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final centerPath = Path();
    Offset pt(double t) {
      final xTop = size.width / 2;
      final yTop = 0.0;
      final xBot = size.width / 2;
      final yBot = size.height;
      final x = xTop + (xBot - xTop) * t;
      final y = yTop + (yBot - yTop) * t;
      return Offset(x, y);
    }

    const dashLen = 18.0;
    const gap = 14.0;
    final total = size.height;
    double start = (dashOffset * (dashLen + gap)) % (dashLen + gap);
    double y = -start;
    while (y < total) {
      final s = max(0.0, y);
      final e = min(total, y + dashLen);
      if (e > 0) {
        centerPath.moveTo(pt(s / total).dx, pt(s / total).dy);
        centerPath.lineTo(pt(e / total).dx, pt(e / total).dy);
      }
      y += dashLen + gap;
    }
    canvas.drawPath(centerPath, centerPaint);
  }

  @override
  bool shouldRepaint(_RoadPainter oldDelegate) => oldDelegate.dashOffset != dashOffset;
}

// ===== HELPERS =====
Future<String?> _fakePicker(BuildContext context, {required String title, required List<String> types}) async {
  final controller = TextEditingController(text: 'my_file${types.first}');
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'File name',
          helperText: 'Accepted: ${types.join(", ")}',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Select')),
      ],
    ),
  );
}

class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SocialChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      side: BorderSide(color: Colors.white.withOpacity(0.5)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: Colors.white.withOpacity(0.25),
    );
  }
}