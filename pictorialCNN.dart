// FILE: lib/camera_screen.dart
// (This version has the FINAL, CORRECT model logic)

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'pothole_logic_service.dart'; // <-- Imports your "brain"
import 'dart:typed_data';
import 'package:image/image.dart' as img_lib; // For image resizing
import 'dart:isolate';
import 'dart:math'; // For 'max'

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  bool _isDetecting = false;
  final PotholeLogicService _logicService = PotholeLogicService();
  List<PotholeResult> _detections = [];

  // Isolate variables
  Isolate? _isolate;
  late final ReceivePort _receivePort;
  late final SendPort _sendPort;
  
  Size? _previewSize;

  @override
  void initState() {
    super.initState();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _startIsolate();
    await _initializeCamera();
    _sendPort.send('load_model');
  }

  Future<void> _startIsolate() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort.sendPort);

    _receivePort.listen((dynamic message) {
      if (message is List<PotholeResult>) {
        if (mounted) {
          setState(() {
            _detections = message;
          });
        }
      }
      _isDetecting = false;
    });

    _sendPort = await _receivePort.first;
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high, // Use 720p
      enableAudio: false,
    );
    await _cameraController!.initialize();
    
    _previewSize = _cameraController!.value.previewSize;

    if (!mounted) return;
    setState(() {}); // Show camera preview

    _cameraController!.startImageStream((CameraImage cameraImage) {
      if (_isDetecting) return;
      _isDetecting = true;
      
      _sendPort.send(cameraImage);
    });
  }

  // --- THIS IS THE ISOLATE CODE (RUNS ON SEPARATE THREAD) ---
  static void _isolateEntry(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    Interpreter? interpreter;
    final logicService = PotholeLogicService();
    
    const double CONFIDENCE_THRESHOLD = 0.25; // Lowered for testing

    await for (final dynamic message in receivePort) {
      if (message == 'load_model') {
        try {
          interpreter = await Interpreter.fromAsset('assets/bestn3_float16.tflite');
          print("✅ (Isolate) TFLite FLOAT16 model loaded successfully.");
        } catch (e) {
          print("❌ (Isolate) Failed to load model: $e");
        }
        continue;
      }

      if (message is CameraImage && interpreter != null) {
        var flatInputTensor = await _preprocessImage(message);
        if (flatInputTensor == null) {
          sendPort.send(null); 
          continue;
        }

        // --- 1. Reshape Input (This is correct) ---
        var input = flatInputTensor.toList().reshape([1, 640, 640, 3]);
        
        // --- 2. Run Model (THIS IS THE FIX) ---
        // The output shape is [1, 5, 8400]
        var output = List.filled(1 * 5 * 8400, 0.0).reshape([1, 5, 8400]); 
        interpreter.run(input, output);

        // --- 3. Post-process (THIS IS THE FIX) ---
        List<dynamic> detections = [];
        List<int> track_ids = []; 
        
        // Get the channels from the output
        var outputData = output[0]; // This is the [5, 8400] list
        final List<double> x_centers = outputData[0];
        final List<double> y_centers = outputData[1];
        final List<double> widths = outputData[2];
        final List<double> heights = outputData[3];
        final List<double> confidences = outputData[4];

        int detectionsFound = 0;
        double maxConf = 0.0; 

        for (int i = 0; i < 8400; i++) {
          double conf = confidences[i];
          
          if (conf > maxConf) {
             maxConf = conf;
          }

          if (conf > CONFIDENCE_THRESHOLD) { 
            detectionsFound++;
            
            final double x_center = x_centers[i];
            final double y_center = y_centers[i];
            final double w = widths[i];
            final double h = heights[i];
            
            detections.add({
              'rect': {
  'x': max(0, (x_center - w / 2) / 640.0).clamp(0.0, 1.0),
  'y': max(0, (y_center - h / 2) / 640.0).clamp(0.0, 1.0),
  'w': min(1.0, w / 640.0),
  'h': min(1.0, h / 640.0),
},
              'confidenceInClass': conf,
            });
            track_ids.add(i); // Use index as fake ID
          }
        }
        
        print("(Isolate) Max confidence this frame: ${maxConf.toStringAsFixed(2)}");
        
        if (detectionsFound > 0) {
           print("✅ (Isolate) Found $detectionsFound potholes this frame!");
        }

        // --- 4. Call your "brain" ---
        final List<PotholeResult> results = logicService.processDetections(
          detections,
          track_ids,
        );

        // --- 5. Send the final results back to the main thread ---
        sendPort.send(results);

      } else {
        sendPort.send(null); 
      }
    }
  }
  
  @override
  void dispose() {
    _cameraController?.dispose();
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashcam Active')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          _buildBoundingBoxes(),
        ],
      ),
    );
  }

  // --- This Box-Drawing widget is correct ---
 Widget _buildBoundingBoxes() {
  if (_detections.isEmpty || _previewSize == null) return Container();

  final Size screenSize = MediaQuery.of(context).size;
  final Size previewSize = _previewSize!;

  final double scaleX = screenSize.width / previewSize.height;
  final double scaleY = screenSize.height / previewSize.width;

  return Stack(
    children: _detections.map((result) {
      final double x = result.x_norm * previewSize.width * scaleX;
      final double y = result.y_norm * previewSize.height * scaleY;
      final double w = result.w_norm * previewSize.width * scaleX;
      final double h = result.h_norm * previewSize.height * scaleY;

      return Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red, width: 3),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              color: Colors.red.withOpacity(0.6),
              padding: const EdgeInsets.all(2),
              child: Text(
                "Pothole ${(result.confidence * 100).toStringAsFixed(1)}%\n${result.size} (${result.radius.toStringAsFixed(2)}m)",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}



  // --- These pre-processing functions are correct ---
  static Future<Float32List?> _preprocessImage(CameraImage cameraImage) async {
    try {
      final img_lib.Image image = _convertYUV420ToImage(cameraImage);
      final img_lib.Image resizedImage = img_lib.copyResize(image, width: 640, height: 640);
      
      var inputTensor = Float32List(1 * 640 * 640 * 3);
      int pixelIndex = 0;
      for (int y = 0; y < 640; y++) {
        for (int x = 0; x < 640; x++) {
          var pixel = resizedImage.getPixel(x, y);
          inputTensor[pixelIndex++] = pixel.r / 255.0; 
          inputTensor[pixelIndex++] = pixel.g / 255.0;
          inputTensor[pixelIndex++] = pixel.b / 255.0;
        }
      }
      return inputTensor;
    } catch (e) {
      print("❌ Error preprocessing image: $e");
      return null;
    }
  }

  static img_lib.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    final img = img_lib.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final Y = image.planes[0].bytes[index];
        final U = image.planes[1].bytes[uvIndex];
        final V = image.planes[2].bytes[uvIndex];

        int R = (Y + 1.402 * (V - 128)).round();
        int G = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round();
        int B = (Y + 1.772 * (U - 128)).round();

        R = R.clamp(0, 255);
        G = G.clamp(0, 255);
        B = B.clamp(0, 255);

        img.setPixelRgb(x, y, R, G, B);
      }
    }
    return img;
  }
}