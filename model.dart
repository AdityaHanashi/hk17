import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';

class YOLOImageDetection extends StatefulWidget {
  const YOLOImageDetection({super.key});

  @override
  State<YOLOImageDetection> createState() => _YOLOImageDetectionState();
}

class _YOLOImageDetectionState extends State<YOLOImageDetection> {
  Interpreter? _interpreter;
  String _resultText = "Processing...";

  @override
  void initState() {
    super.initState();
    _loadModelAndRun();
  }

  Future<void> _loadModelAndRun() async {
    try {
      // Load YOLO model (.tflite)
      _interpreter = await Interpreter.fromAsset('bestn2.tflite');

      // Load input image (from assets)
      final imageFile = File('assets/img90.jpg');
      final image = img.decodeImage(await imageFile.readAsBytes());

      if (image == null) {
        setState(() => _resultText = "Failed to load image.");
        return;
      }

      // Resize image to model input size (e.g., 640x640)
      final resized = img.copyResize(image, width: 640, height: 640);
      final input = List.generate(1,
          () => List.generate(640, () => List.generate(640, (_) => List.filled(3, 0.0))));

      // Fill input tensor with pixel data
      for (int y = 0; y < 640; y++) {
        for (int x = 0; x < 640; x++) {
          final pixel = resized.getPixel(x, y);
          input[0][y][x][0] = img.getRed(pixel) / 255.0;
          input[0][y][x][1] = img.getGreen(pixel) / 255.0;
          input[0][y][x][2] = img.getBlue(pixel) / 255.0;
        }
      }

      // Prepare output buffer
      var output = List.filled(1 * 25200 * 85, 0.0).reshape([1, 25200, 85]);

      // Run inference
      _interpreter!.run(input, output);

      // Parse results (simplified)
      setState(() {
        _resultText = "Detection complete. Found objects = ${output[0].length}";
      });
    } catch (e) {
      setState(() => _resultText = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("YOLO Image Detection"),
        backgroundColor: Colors.indigo,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _resultText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}