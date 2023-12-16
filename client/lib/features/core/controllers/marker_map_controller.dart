import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:custom_info_window/custom_info_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hestia/data/repositories/firebase_query_repository/firebase_query_for_users.dart';
import 'package:hestia/features/core/screens/maps/MarkerMap/AddMarkerDetailsScreen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';

class MarkerMapController extends GetxController {
  static MarkerMapController get instance => Get.find();

  // -- CHANGING MAP TYPE
  final Rx<MapType> _currentMapType = MapType.normal.obs;
  MapType get currentMapType => _currentMapType.value;
  void toggleMap() {
    _currentMapType.value = _currentMapType.value == MapType.normal
        ? MapType.satellite
        : MapType.normal;
  }

  // -- MARKERS
  RxSet<Marker> markers = <Marker>{}.obs;
  RxSet<Marker> fixedMarkers = <Marker>{}.obs;

  // Add Markers when tapped
  void addTapMarkers(LatLng position, int id) {
    markers.clear();
    markers.add(
      Marker(
        markerId: MarkerId('$id'),
        position: position,
        draggable: true,
        onDragEnd: (value) => tapPosition = value,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    markers.addAll(fixedMarkers);
  }

  // Delete all the Markers except which are fixed
  void deleteMarkersExceptFixed() {
    markers
      ..clear()
      ..addAll(fixedMarkers);
  }

  // Add a specific made up marker (but not adding Current Location in fixed)
  void addSpecificMarker(Marker marker, bool isCurr) {
    markers.add(marker);
    if (!isCurr) fixedMarkers.add(marker);
  }

  // Home Marker Add (To navigate Back to home)
  void homeMarkerAdd(Marker marker) {
    markers
      ..clear()
      ..add(marker);

    markers.addAll(fixedMarkers);
  }

  // -- CURRENT POSITION
  Rx<LatLng?> currPos = Rx<LatLng?>(null);

  void updateCurrPos(LatLng latLng) {
    currPos.value = latLng;
  }

  // -- CUSTOM INFO CONTROLLER OF MARKER
  Rx<CustomInfoWindowController> customInfoWindowController =
      CustomInfoWindowController().obs;

  void updateGoogleControllerForCustomInfoWindowController(
      GoogleMapController googleMapController) {
    customInfoWindowController.value.googleMapController = googleMapController;
  }

  // ------------------------------- VARIABLES (NON OBSERVABLE) --------------------------

  // Used to get the current location
  final Location locationController = Location();

  // Random Camera Position at Google Plex
  static const CameraPosition kGooglePlex =
      CameraPosition(target: LatLng(37.42, -125.08), zoom: 13);

  // Tracks the current Tapped Lat & Long (Position) => For Camera Mechanism
  LatLng? tapPosition;

  // -- Unique MarkerId & Image
  int id = 1;
  late File image = File('');

  // -- Animate Camera to current Location
  late final GoogleMapController googleMapController;

  // ------------------------------- FUNCTIONS ---------------------------------

  // -- Take permission and get current location
  Future<void> getUserLocation() async {
    try {
      bool serviceEnabled;
      PermissionStatus permissionGranted;

      serviceEnabled = await MarkerMapController.instance.locationController
          .serviceEnabled();

      if (!serviceEnabled) {
        serviceEnabled = await MarkerMapController.instance.locationController
            .requestService();
        if (!serviceEnabled) {
          return;
        }
      }

      permissionGranted =
          await MarkerMapController.instance.locationController.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await MarkerMapController
            .instance.locationController
            .requestPermission();

        if (permissionGranted != PermissionStatus.granted) {
          updateCurrPos(LatLng(
              kGooglePlex.target.latitude, kGooglePlex.target.longitude));

          return;
        }
      }

      LocationData currentLocation =
          await MarkerMapController.instance.locationController.getLocation();

      updateCurrPos(
          LatLng(currentLocation.latitude!, currentLocation.longitude!));

      Marker currPosMarker = Marker(
        markerId: const MarkerId('currentLocation'),
        position: currPos.value!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(
          title: "Your Current Location",
        ),
      );
      addSpecificMarker(currPosMarker, true);
    } catch (e) {
      print("Error getting user location: $e");
    }
  }

  // -- Open Camera / Gallery for Marker Description
  Future<void> getImage(bool isCamera) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: isCamera ? ImageSource.camera : ImageSource.gallery,
      );

      if (pickedFile != null) {
        File image = File(pickedFile.path);

        // Use 'await' when navigating to ImageScreen
        Marker? result = await Get.to(
          () => ImageScreen(
            image: image,
            position: tapPosition!,
            id: id,
            customInfoWindowController: customInfoWindowController.value,
          ),
        );

        // If 'result' is not null, it means the user posted an image
        if (result != null) {
          // Add the returned marker to the _markers list
          addSpecificMarker(result, false);
          id++;
        }
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  // -- Add the marker of the current location and move the camera there
  Future<void> moveToCurrLocation() async {
    googleMapController
        .animateCamera(CameraUpdate.newLatLngZoom(currPos.value!, 13));

    final marker = Marker(
        markerId: const MarkerId("currentLocation"),
        position: currPos.value!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: "Current Location"));

    homeMarkerAdd(marker);
  }

  // -- Making Custom Markers
  Marker MakeFixedMarker(
      int id,
      LatLng position,
      CustomInfoWindowController customInfoWindowController,
      String desc,
      File image) {
    return Marker(
      markerId: MarkerId('$id'),
      position: position,
      draggable: true,
      onDrag: (LatLng value) {
        customInfoWindowController.hideInfoWindow!();

        // Store the new position
        position = value;

        // Add a new info window at the updated position
        customInfoWindowController.addInfoWindow!(
          infoWindow(desc, image),
          value,
        );
      },
      onTap: () {
        customInfoWindowController.addInfoWindow!(
          infoWindow(desc, image),
          position,
        );
      },
      icon: BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      ),
    );
  }

  // -- Making Custom Info Window For Custom Marker (or Fixed Markers)
  Widget infoWindow(String text, File image) {
    return Container(
      width: 250,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 280,
            height: 100,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: FileImage(image),
                fit: BoxFit.fitWidth,
                filterQuality: FilterQuality.high,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(15.0)),
              color: Colors.red[400],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Get Image From URL (Use to get the firebase Storage Images)
  Future<File> getImageFile(String imageUrl) async {
    final response = await http.get(Uri.parse(imageUrl));

    if (response.statusCode == 200) {
      // Convert the response body to bytes
      Uint8List bytes = response.bodyBytes;

      // Get the app's temporary directory
      Directory tempDir = await getTemporaryDirectory();

      // Create the necessary directories
      String appDirPath = '${tempDir.path}/HESTIA/MarkerImages/';
      Directory(appDirPath).createSync(recursive: true);

      // Create a temporary file in the app's temporary directory
      File imageFile = File('$appDirPath/image_file${id}.png');

      // Write the bytes to the file
      await imageFile.writeAsBytes(bytes);

      return imageFile;
    } else {
      throw Exception('Failed to load image');
    }
  }

  // -- Make Markers from Firestore Maps (& store it in fixed markers)
  Future<void> makeMarkersFromFirestoreMaps() async {
    var listofmaps = await FirebaseQueryForUsers().getMarkersFromUsers();

    for (var map in listofmaps) {
      LatLng position = LatLng(map["lat"], map["long"]);
      File? image = await getImageFile(map["imageUrl"]);
      Marker marker = MakeFixedMarker(
          ++id,
          position,
          customInfoWindowController.value,
          map["description"],
          image != null ? image : File(""));

      // Adding the marker to markers & fixed Markers list
      addSpecificMarker(marker, false);
    }
  }
}
