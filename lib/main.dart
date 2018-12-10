import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:async/async.dart';
import 'package:http/http.dart' as http;
import 'package:splashscreen/splashscreen.dart';
import 'package:audioplayer/audioplayer.dart';

class CameraExampleHome extends StatefulWidget {
  @override
  _CameraExampleHomeState createState() {
    return _CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  throw ArgumentError('Unknown lens direction');
}

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

class _CameraExampleHomeState extends State<CameraExampleHome> {
  CameraController controller;
  bool pictureTaken = false;
  String imagePath;
  String predictionResult;
  String videoPath;
  VoidCallback videoPlayerListener;
  AudioPlayer audioPlugin = AudioPlayer();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Drushti : AI Vision', textAlign: TextAlign.center),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              child: Center(
                child: _cameraPreviewWidget(),
              ),
              /*
              decoration: BoxDecoration(
                color: Colors.black12,
                border: Border.all(
                  color: controller != null && controller.value.isRecordingVideo
                      ? Colors.redAccent
                      : Colors.grey,
                  width: 1.0,
                ),
              ),*/
            ),
          ),
          _captureControlRowWidget(),
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                _cameraTogglesRowWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      return Container();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: CameraPreview(controller),
    );
  }

  Widget getProperWidget() {
    if (pictureTaken)
      return new CircularProgressIndicator();
    else {
      //showInSnackBar('Prediction Result: $predictionResult');
      synthesizeText(predictionResult);
      return new Text('$predictionResult');
    }
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    bool pressed = false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        RaisedButton(
          color: pressed ? Colors.green : Colors.blue,
          onPressed: () {
            setState(() {
              pressed = !pressed;
              pictureTaken = true;
            });
            if (controller != null &&
                controller.value.isInitialized &&
                !controller.value.isRecordingVideo)
              onTakePictureButtonPressed();
          },
          shape: new RoundedRectangleBorder(
              borderRadius: new BorderRadius.circular(5.0)),
          padding: EdgeInsets.all(15.0),
          child:
              new Text("Get Prediction", style: TextStyle(color: Colors.white)),
        ),
        getProperWidget()
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        toggles.add(
          SizedBox(
            width: 120.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: controller != null && controller.value.isRecordingVideo
                  ? null
                  : onNewCameraSelected,
            ),
          ),
        );
      }
    }

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(cameraDescription, ResolutionPreset.high);

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        showInSnackBar('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((String filePath) {
      if (mounted) {
        setState(() {
          imagePath = filePath;
        });
        //if (filePath != null) showInSnackBar('Picture saved to $filePath');
        upload(File(filePath));
      }
    });
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void upload(File imageFile) async {
    try {
      // open a bytestream
      var stream =
          new http.ByteStream(DelegatingStream.typed(imageFile.openRead()));
      // get file length
      var length = await imageFile.length();

      // string to uri
      var uri = Uri.parse("http://52.202.144.158:5000/predict");

      // create multipart request
      var request = new http.MultipartRequest("POST", uri);

      // multipart that takes file
      var multipartFile = new http.MultipartFile('image', stream, length,
          filename: basename(imageFile.path));

      // add file to multipart
      request.files.add(multipartFile);

      // send
      var response = await request.send();
      response.stream.transform(utf8.decoder).listen((value) {
        var resultsOBj = Results.fromJson(json.decode(value));
        setState(() {
          pictureTaken = false;
          predictionResult = resultsOBj.prediction.toString();
        });
      });
    } on Exception catch (e) {
      logError(e.toString(), 'error');
      return null;
    }
  }

  void synthesizeText(String text) async {
    if (audioPlugin.state == AudioPlayerState.PLAYING) {
      await audioPlugin.stop();
    }
    final String audioContent = await TextToSpeechAPI().synthesizeText(text);
    if (audioContent == null) return;
    final bytes = Base64Decoder().convert(audioContent, 0, audioContent.length);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wavenet.mp3');
    await file.writeAsBytes(bytes);
    await audioPlugin.play(file.path, isLocal: true);
  }
}

class CameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> cameras;

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description);
  }
  runApp(CameraApp());
}

class Results {
  String prediction;
  bool success;

  Results({this.prediction = '', this.success = false});

  factory Results.fromJson(Map<String, dynamic> json) {
    return Results(prediction: json['prediction'], success: json['success']);
  }
}

class TextToSpeechAPI {
  static final TextToSpeechAPI _singleton = TextToSpeechAPI._internal();
  final _httpClient = HttpClient();
  static const _apiKey = "AIzaSyB8Xe4EbMCHSAIAWGIEvijZC20NVrBZQio";
  static const _apiURL = "texttospeech.googleapis.com";

  factory TextToSpeechAPI() {
    return _singleton;
  }

  TextToSpeechAPI._internal();

  Future<dynamic> synthesizeText(String text) async {
    try {
      final uri = Uri.https(_apiURL, '/v1/text:synthesize');
      final Map json = {
        'input': {'text': text},
        'voice': {'name': 'en-US-Wavenet-C', 'languageCode': 'en-US'},
        'audioConfig': {'audioEncoding': 'MP3'}
      };

      final jsonResponse = await _postJson(uri, json);
      if (jsonResponse == null) return null;
      final String audioContent = await jsonResponse['audioContent'];
      return audioContent;
    } on Exception catch (e) {
      print("$e");
      return null;
    }
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map jsonMap) async {
    try {
      final httpRequest = await _httpClient.postUrl(uri);
      final jsonData = utf8.encode(json.encode(jsonMap));
      final jsonResponse =
          await _processRequestIntoJsonResponse(httpRequest, jsonData);
      return jsonResponse;
    } on Exception catch (e) {
      print("$e");
      return null;
    }
  }

  Future<Map<String, dynamic>> _processRequestIntoJsonResponse(
      HttpClientRequest httpRequest, List<int> data) async {
    try {
      httpRequest.headers.add('X-Goog-Api-Key', _apiKey);
      httpRequest.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
      if (data != null) {
        httpRequest.add(data);
      }
      final httpResponse = await httpRequest.close();
      if (httpResponse.statusCode != HttpStatus.OK) {
        throw Exception('Bad Response');
      }
      final responseBody = await httpResponse.transform(utf8.decoder).join();
      return json.decode(responseBody);
    } on Exception catch (e) {
      print("$e");
      return null;
    }
  }
}
