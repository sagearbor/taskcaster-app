# Report on AR Flutter Plugin 2

This report is organized and analyzed based on all the relevant code in the repository [ar_flutter_plugin_2](https://github.com/hlefe/ar_flutter_plugin_2). This plugin is a Flutter AR (Augmented Reality) plugin that implements ARCore support on Android (via [sceneview-android](https://github.com/sceneview/sceneview-android)) and ARKit support on iOS, while also integrating the Google Cloud Anchor API for shared/cloud anchor functionalities.

The article focuses on the following aspects:

1. **Overall Plugin Architecture (Architecture)**
2. **Implementation on the Flutter Side (Plugin - Flutter)** **(Key)**
3. **Implementation on the iOS Platform (Plugin - iOS)**
4. **Implementation on the Android Platform (Plugin - Android)** **(Key)**
5. **How to Interact with SceneView for AR**
6. **How to Use This Plugin** **(Key)**

The report will explain each section in separate chapters and include some key code snippets to illustrate the implementation details.

---

## 1. Overall Plugin Architecture

![[Pasted image 20250220205042.png]]

The main goal of this plugin is to provide cross-platform (Android / iOS) AR functionalities for Flutter, including:

- Creating an AR Session (including camera preview)
- Detecting planes in the AR scene, placing virtual objects, and handling anchors
- Implementation on Android based on sceneview-android
- On iOS, integrating ARKit along with partial cloud functionalities via Google ARCore/Cloud Anchor

The diagram below shows a high-level architectural overview provided in the repository (see `AR_Plugin_Architecture_highlevel.svg`). It demonstrates that the Flutter side calls the platform channel, while the native modules in Android and iOS respectively invoke ARCore/ARKit along with their rendering engines or Cloud Anchor services:

```
Flutter (Dart)
  ├─ ARSessionManager / ARObjectManager / ARAnchorManager
  ├─ ...
  └─ Platform Channel
      ├─ Android native code (Kotlin)
      │    └─ sceneview-android
      └─ iOS native code (Swift/ObjC)
           └─ ARKit + ARCore Cloud Anchor
```

From a code perspective, the Flutter layer mainly provides several managers (e.g., `ARSessionManager`, `ARObjectManager`, `ARAnchorManager`, `ARLocationManager`, etc.) that interact with the native side via MethodChannel. On the native side (Android/iOS), corresponding factories, view classes, and method handlers receive calls from Flutter and handle the AR logic.

---

## 2. Implementation on the Flutter Side (Plugin - Flutter)

The Flutter side is mainly divided into the following key parts:

1. **`ar_flutter_plugin.dart`**

   - This is a simple export file that exports some externally available `ARView` widget.
   - It also defines an `ArFlutterPlugin` class internally as a placeholder, while the actual core functionality is implemented elsewhere.

2. **`widgets/ar_view.dart`**

   - This is the core widget exposed to the Flutter layer — `ARView`.
   - Its usage is similar to a conventional Flutter PlatformView: in the `build` method, it checks for camera permissions. If granted, it creates a platform view (either `UiKitView` or `AndroidView`); otherwise, it presents a permission prompt.
   - The `ARView` returns a series of managers (such as `ARSessionManager`, etc.) to the upper layer via the `onARViewCreated` callback.
   - The core logic is illustrated below:

     ```dart
     class ARView extends StatefulWidget {
       // ...
       final ARViewCreatedCallback onARViewCreated;
       // ...
     }

     class _ARViewState extends State<ARView> {
       @override
       build(BuildContext context) {
         if (cameraPermissionGranted) {
           return PlatformARView(...).build(...);
         } else {
           return Center(
             child: // Prompt to grant camera permission
           );
         }
       }
     }
     ```

3. **Manager Classes:**

   - **`ARSessionManager`**: Manages AR session configurations and events, such as plane detection, camera pose retrieval, snapshots, etc.
   - **`ARObjectManager`**: Manages nodes within the 3D scene (including loading/removing 3D models and handling gestures such as dragging/rotating nodes).
   - **`ARAnchorManager`**: Manages anchors (adding/removing anchors or synchronizing with cloud anchors).
   - **`ARLocationManager`**: Encapsulates location management to obtain geolocation, permissions, etc.
   - These managers interact with native implementations via `MethodChannel`. For example:
     ```dart
     class ARSessionManager {
       // ...
       onInitialize(...) => _channel.invokeMethod<void>('init', { ... });
       getCameraPose() => _channel.invokeMethod<List>('getCameraPose', {});
       // ...
     }
     ```

4. **`datatypes` Directory:**

   - Contains some enum classes (for example, `NodeType`, `AnchorType`, `PlaneDetectionConfig`) and data structures (for example, `ARHitTestResult`).
   - Here, `NodeType` indicates the node loading method (local gltf / web glb / file system, etc.).
   - `PlaneDetectionConfig` indicates the type of plane detection (horizontal/vertical/all/disabled).

5. **`models` Directory:**

   - Contains classes such as `ARNode` and `ARAnchor`, representing virtual nodes and anchors in the scene.

### Key Code Sample on the Flutter Side

**Adding a 3D Node:**

```dart
// Flutter side
bool? didAddNode = await arObjectManager.addNode(
    ARNode(
      type: NodeType.webGLB,
      uri: "https://xxx/Duck.glb",
      scale: Vector3(0.2, 0.2, 0.2),
      name: "my3DNode",
    )
);
```

This will invoke the corresponding implementation on Android or iOS via the `MethodChannel` to load the glb model and insert it into the scene.

---

## 3. Implementation on the iOS Platform (Plugin - iOS)

The core entry point on the iOS side is `SwiftArFlutterPlugin.swift`, where an `IosARViewFactory` is registered to return a custom `IosARView`.

### Key iOS Classes

- **`IosARViewFactory.swift`**  
   Implements the Flutter PlatformViewFactory protocol, returning an `IosARView` object through the `create()` method.
- **`IosARView.swift`**
  - Inherits from `NSObject, FlutterPlatformView` and internally maintains an `ARSCNView` (a view combining SceneKit and ARKit).
  - Implements `ARSessionDelegate` / `ARSCNViewDelegate` to handle rendering events, plane detection events, etc.
  - Uses `_channel.setMethodCallHandler` to process calls from Flutter, such as initialization, adding/removing nodes, adding/removing anchors, and uploading/downloading Cloud Anchors.
- **Cloud Anchor**
  - On iOS, `ARCoreCloudAnchors` (i.e., `GARSession`) is used to implement cloud anchor hosting and resolving, with the logic encapsulated in `CloudAnchorHandler.swift` that handles Google ARCore session operations.
  - JWT is required for authentication; hence, `JWTGenerator.swift` implements the reading and signing of the service account key from `cloudAnchorKey.json`.
- **ARCore + ARKit**  
   iOS runs a local AR session using ARKit while using ARCore’s `GARSession` to synchronize anchors with the cloud.

---

## 4. Implementation on the Android Platform (Plugin - Android)

The main structure on the Android side includes:

1. **`ArFlutterPlugin.kt`**

   - Implements the entry points for the Flutter plugin: `onAttachedToEngine` / `onDetachedFromEngine` / `onAttachedToActivity`, etc.
   - When the plugin is created by Flutter, it registers an `ArViewFactory` and listens for Activity lifecycle events.

2. **`ArViewFactory.kt`**

   - Implements `PlatformViewFactory`; when the Flutter side creates a view, it returns a custom `ArView`.

3. **`ArView.kt`**

   - The core logic class in Kotlin, inheriting from `PlatformView`.
   - Internally maintains an `ARSceneView` (from [sceneview-android](https://github.com/sceneview/sceneview-android)), and handles node loading, plane detection, and cloud anchors through various callbacks (such as `onFrame` and `onGestureListener`).
   - It distinguishes among three MethodChannels: `sessionChannel`, `objectChannel`, and `anchorChannel`:
     - **`sessionChannel`**: Manages session initialization, toggling plane visibility, taking camera snapshots, etc.
     - **`objectChannel`**: Manages adding/removing nodes and handling changes in their transforms.
     - **`anchorChannel`**: Manages anchor creation/removal as well as uploading/downloading Cloud Anchors.
   - In `ArView`, the process of loading a 3D model is shown as:
     ```kotlin
     private suspend fun buildModelNode(nodeData: Map<String, Any>): ModelNode? {
         // ...
         when (nodeData["type"] as Int) {
             0 -> { // GLTF2 Model from Flutter asset
               // ...
             }
             1 -> { // GLB Model from the web
               // ...
             }
             // ...
         }
         // The model is loaded via sceneView.modelLoader.loadModelInstance(...)
     }
     ```
   - It also handles Cloud Anchors with methods such as `initGoogleCloudAnchorMode`, `uploadAnchor`, and `downloadAnchor`.

4. **`HandMotionView` / `HandMotionAnimation`**

   - Provides an animated guide view (displaying a phone along with gesture animations) to prompt users for plane scanning.

5. **`Serialization` Directory**

   - Handles serialization and deserialization between Flutter and Kotlin, such as serializing matrices and hit results.

6. **`android/build.gradle`**

   - Depends on `io.github.sceneview:arsceneview:2.2.1` and the Flutter embedding debug library.

### Key Interaction Example

For example, when adding a node, the Flutter side calls `objectChannel.invokeMethod("addNode", nodeMap)`, and the Kotlin side in `ArView.kt` receives this via `onObjectMethodCall`, then executes `handleAddNode` followed by a call to `sceneView.modelLoader.loadModelInstance(...)` to add the node to ARSceneView upon successful loading.

---

## 5. How to Interact with SceneView for AR

> **SceneView** is the 3D/AR rendering library used on Android (replacing the older Sceneform).  
> On iOS, ARKit combined with SceneKit is used.

Common interaction methods include:

1. **Adding a Node**

   - On the Flutter side:
     ```dart
     var newNode = ARNode(type: NodeType.webGLB, uri: "http://xxx/model.glb", ...);
     bool? didAddNode = await arObjectManager.addNode(newNode);
     ```
   - On the native side (in Android’s `ArView.kt`), the glb model is downloaded/loaded via `sceneView.modelLoader.loadModelInstance(...)` which creates a ModelNode and adds it as a child node to ARSceneView.

2. **Removing a Node**

   - On Flutter: `arObjectManager.removeNode(node);`
   - On Android/iOS: The node is found (usually by its name) and removed from the scene.

3. **Gesture Interaction (Panning / Rotation)**

   - On Flutter: Initialize parameters such as `handlePans: true, handleRotation: true`.
   - In Android’s `ArView.kt`: A gesture listener is set up via `setOnGestureListener(...)` to listen for events like `onMoveBegin` and `onRotateBegin`, which are then passed back to Flutter (e.g., `onPanStart`, `onRotationEnd`).

4. **Plane Detection**

   - Configured through SessionManager: e.g., `planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical`
   - When a new plane is detected, the Android side checks the number of planes in the `onFrame` callback and sends an `onPlaneDetected` callback to Flutter.

5. **Cloud Anchor**

   - On the Flutter side: Methods such as `arAnchorManager.initGoogleCloudAnchorMode()`, `uploadAnchor(...)`, and `downloadAnchor(...)` are used.
   - On the Android side: It checks for sufficient feature points via `sceneView.session?.canHostCloudAnchor(...)` and, if conditions are met, proceeds to host or resolve the anchor.

---

## 6. How to Use This Plugin

### Basic Steps

1. **Add the dependency in pubspec.yaml:**

   ```yaml
   dependencies:
     ar_flutter_plugin_2: ^0.0.3
   ```

2. **Add Camera Permissions on iOS**

   - In `ios/Runner/Info.plist`, add:
     ```xml
     <key>NSCameraUsageDescription</key>
     <string>Camera is required for AR functionalities</string>
     ```
   - If compiling/running in FlutterFlow, add a camera permission description in “App Settings” → “Permissions” or manually modify the Podfile to enable `PERMISSION_CAMERA=1`.

3. **Import and Place the `ARView`:**

   ```dart
   import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';

   class MyARPage extends StatefulWidget { ... }

   class _MyARPageState extends State<MyARPage> {
     ARSessionManager? arSessionManager;
     ARObjectManager? arObjectManager;
     ARAnchorManager? arAnchorManager;
     ARLocationManager? arLocationManager;

     @override
     Widget build(BuildContext context) {
       return Scaffold(
         appBar: AppBar(title: Text('AR Demo')),
         body: ARView(
           onARViewCreated: onARViewCreated,
           planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
         )
       );
     }

     void onARViewCreated(
       ARSessionManager sessionManager,
       ARObjectManager objectManager,
       ARAnchorManager anchorManager,
       ARLocationManager locationManager
     ) {
       this.arSessionManager = sessionManager;
       this.arObjectManager = objectManager;
       this.arAnchorManager = anchorManager;
       this.arLocationManager = locationManager;

       // Initialize the AR Session
       arSessionManager?.onInitialize(
         showFeaturePoints: false,
         showPlanes: true,
         customPlaneTexturePath: "Images/triangle.png",
         showWorldOrigin: false,
         handleTaps: true,
         handlePans: true,
         handleRotation: true,
       );

       // Initialize ObjectManager
       arObjectManager?.onInitialize();

       // Additional configuration for anchorManager and locationManager can also be set
     }
   }
   ```

4. **Operate Within the Scene**

   - **Adding a 3D Node**
     ```dart
     var newNode = ARNode(
       type: NodeType.localGLTF2,
       uri: "Models/Chicken_01/Chicken_01.gltf", // Flutter asset
       scale: Vector3(0.2, 0.2, 0.2),
       name: "myChicken"
     );
     bool? didAddNode = await arObjectManager?.addNode(newNode);
     ```
   - **Removing a 3D Node**
     ```dart
     arObjectManager?.removeNode(newNode);
     ```
   - **Adding an Anchor**
     ```dart
     // Create a planeAnchor directly
     var anchor = ARPlaneAnchor(
       transformation: someMatrix, // 4x4 matrix
       name: "myAnchor"
     );
     arAnchorManager?.addAnchor(anchor);
     ```
   - **Enabling Cloud Anchor Mode**

     ```dart
     // Enable cloud anchor mode
     arAnchorManager?.initGoogleCloudAnchorMode();

     // Upload an anchor
     arAnchorManager?.uploadAnchor(anchor);

     // Download an anchor
     arAnchorManager?.downloadAnchor("cloudAnchorIdxxxxx");
     ```

5. **Gesture Control**

   - If you set `handlePans: true, handleRotation: true` in the `onInitialize` method, you can drag/rotate nodes in the scene.
   - The Flutter side will receive callbacks such as `onPanStart`, `onPanEnd`, and `onRotationEnd` (which can be defined in the `ARObjectManager`).

6. **Releasing Resources**

   - When exiting the page, call `arSessionManager?.dispose()` to stop the native AR session and free memory.

### Typical Examples

The repository’s `examples` folder contains many examples, such as `cloud_anchor.dart` and `object_gestures.dart`. Each file demonstrates how to implement the AR logic after receiving the managers from `onARViewCreated`.

---

## Summary

The `ar_flutter_plugin_2` builds an easy-to-use API on the Flutter side using several managers (`ARSessionManager`, `ARObjectManager`, `ARAnchorManager`, `ARLocationManager`, etc.) to manage the underlying native AR SDKs (with Android using SceneView + ARCore and iOS using ARKit + ARCore Cloud Anchors). The key features include:

- Plane detection and rendering
- 3D model loading (local, web, or app file system)
- Gesture operations (moving and rotating 3D nodes)
- Cloud Anchors (for shared scenes)
- Camera snapshots

The main steps for using the plugin are: add the dependency, configure camera permissions on iOS/Android, place the `ARView` widget in Flutter, initialize the managers in the `onARViewCreated` callback, and subsequently operate on AR scenes and nodes using various manager methods. The plugin also has additional compatibility considerations for FlutterFlow.

For more detailed information, please refer to:

- The examples contained in the `examples/` folder
- [cloudAnchorSetup.md](https://github.com/hlefe/ar_flutter_plugin_2/blob/main/cloudAnchorSetup.md) for details on Cloud Anchors
- The default `README.md` and source code comments

If you wish to customize the underlying implementation, you can further modify the native code for Android (`ArView.kt` / `ArViewFactory.kt`) or iOS (`IosARView.swift` / `CloudAnchorHandler.swift`). The plugin is currently under continuous development, and contributions via Issues or PRs are very welcome.

---
