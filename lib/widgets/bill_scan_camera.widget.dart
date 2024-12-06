import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Widget used to read the barcode using phone's camera.
class BillScanCameraWidget extends StatefulWidget {
  const BillScanCameraWidget({
    required this.onImage,
    this.initialDirection = CameraLensDirection.back,
    super.key,
  });

  final Function(List<Barcode> barcodes) onImage;
  final CameraLensDirection initialDirection;

  @override
  BillScanCameraWidgetState createState() => BillScanCameraWidgetState();
}

class BillScanCameraWidgetState extends State<BillScanCameraWidget> {
  /// Camera list.
  List<CameraDescription> cameras = [];

  /// Controller for the camera.
  CameraController? cameraController;

  /// Camera being used for scanning.
  int? _cameraIndex;

  /// Zoom levels.
  double zoomLevel = 1.0, minZoomLevel = 0.0;

  bool _isBusy = false;

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Scanner for reading barcode images.
  final BarcodeScanner barcodeScanner = BarcodeScanner(formats: [
    BarcodeFormat.itf,
    BarcodeFormat.codabar,
  ]);

  @override
  void initState() {
    super.initState();
    initStreams();
  }

  @override
  void dispose() {
    stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return cameraController?.value.isInitialized == true
        ? Container(
            height: double.infinity,
            width: double.infinity,
            color: Colors.black,
            child: Center(child: CameraPreview(cameraController!)),
          )
        : Container();
  }

  /// Initialize event streams used to process camera images.
  void initStreams() async {
    cameras = await availableCameras();
    for (var i = 0; i < cameras.length; i++) {
      if (cameras[i].lensDirection == widget.initialDirection &&
          _cameraIndex == null) {
        _cameraIndex = i;
      }
    }

    startLiveFeed();
  }

  /// Begins camera livestream.
  Future<void> startLiveFeed() async {
    final camera = cameras[_cameraIndex ?? 0];
    cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await cameraController?.initialize();

    if (!mounted) return;

    cameraController?.getMinZoomLevel().then((value) {
      zoomLevel = value;
      minZoomLevel = value;
    });

    cameraController
        ?.setZoomLevel(zoomLevel > minZoomLevel ? zoomLevel : minZoomLevel);

    if (Platform.isIOS) {
      cameraController?.lockCaptureOrientation(DeviceOrientation.portraitUp);
    }

    cameraController?.startImageStream(_processCameraImage);
    setState(() {});
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = convertsCameraImage(image);
    if (inputImage == null) return;
    if (_isBusy) return;
    _isBusy = true;
    barcodeScanner
        .processImage(inputImage)
        .then(widget.onImage)
        .whenComplete(() => _isBusy = false);
  }

  /// Stops camera livestream.
  Future stopLiveFeed() async {
    await cameraController?.stopImageStream();
    await cameraController?.dispose();
  }

  /// Sends captured image to be converted from [CameraImage] type into [InputImage] type.
  ///
  /// The converted imaged is received by [listenBarcodes] method.
  InputImage? convertsCameraImage(CameraImage image) {
    if (cameraController == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = cameras[_cameraIndex ?? 0];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (Platform.isAndroid && format == InputImageFormat.yuv_420_888) {
      Uint8List nv21Data = convertYUV420ToNV21(image);

      return InputImage.fromBytes(
        bytes: nv21Data,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid &&
            (format != InputImageFormat.nv21 ||
                format != InputImageFormat.yuv_420_888)) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }

  Uint8List convertYUV420ToNV21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    // Planes from CameraImage
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    // Buffers from Y, U, and V planes
    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    // Total number of pixels in NV21 format
    final numPixels = width * height + (width * height ~/ 2);
    final nv21 = Uint8List(numPixels);

    // Y (Luma) plane metadata
    int idY = 0;
    int idUV = width * height; // Start UV after Y plane
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;

    // Strides and pixel strides for Y and UV planes
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;

    // Copy Y (Luma) channel
    for (int y = 0; y < height; ++y) {
      final yOffset = y * yRowStride;
      for (int x = 0; x < width; ++x) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];
      }
    }

    // Copy UV (Chroma) channels in NV21 format (YYYYVU interleaved)
    for (int y = 0; y < uvHeight; ++y) {
      final uvOffset = y * uvRowStride;
      for (int x = 0; x < uvWidth; ++x) {
        final bufferIndex = uvOffset + (x * uvPixelStride);
        nv21[idUV++] = vBuffer[bufferIndex]; // V channel
        nv21[idUV++] = uBuffer[bufferIndex]; // U channel
      }
    }

    return nv21;
  }
}
