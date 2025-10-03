import 'dart:typed_data';
import 'dart:io'; // for File
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Upload image to Firebase Storage
  Future<String> uploadImageToStorage(
      String childName, Uint8List file, bool isPost,
      {String contentType = 'image/jpeg'}) async {
    try {
      Reference ref =
          _storage.ref().child(childName).child(_auth.currentUser!.uid);
      if (isPost) {
        String id = const Uuid().v1();
        ref = ref.child(id);
      }

      final metadata = SettableMetadata(contentType: contentType);
      UploadTask uploadTask = ref.putData(file, metadata);
      TaskSnapshot snapshot = await uploadTask;

      final parentRef = snapshot.ref.parent!;
      final thumbRef = parentRef.child('${snapshot.ref.name}_1024x1024');

      String? downloadUrl;
      int retries = 0;
      const int maxRetries = 10;

      while (retries < maxRetries) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          downloadUrl = await thumbRef.getDownloadURL();
          break;
        } catch (e) {
          retries++;
        }
      }

      if (downloadUrl == null) {
        throw Exception(
            'Resized image not available after $maxRetries attempts');
      }

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // Delete an image from Firebase Storage
  Future<void> deleteImage(String imageUrl) async {
    try {
      if (!imageUrl.startsWith('gs://') &&
          !imageUrl.contains('firebasestorage.googleapis.com')) {
        throw Exception('Invalid Firebase Storage URL: $imageUrl');
      }

      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      rethrow;
    }
  }

  // Fixed: Create a temporary file from Uint8List and upload it
  Future<String> uploadVideoToSupabase(
      String bucketName, Uint8List file, String fileName) async {
    try {
      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create a temporary file
      final tempFile = await _createTempFile(uniqueFileName, file);

      // Upload the File object (not Uint8List)
      final response = await _supabase.storage
          .from(bucketName)
          .upload(uniqueFileName, tempFile);

      // Clean up the temporary file
      await tempFile.delete();

      // Get public URL
      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(uniqueFileName);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video to Supabase: $e');
    }
  }

  // Helper method to create a temporary file
  Future<File> _createTempFile(String fileName, Uint8List data) async {
    try {
      // Method 1: Try to use system temp directory
      final systemTemp = Directory.systemTemp;
      if (await systemTemp.exists()) {
        final tempFile = File('${systemTemp.path}/$fileName');
        await tempFile.writeAsBytes(data);
        return tempFile;
      }
    } catch (e) {
      // Fall through to next method
    }

    try {
      // Method 2: Try current directory
      final currentDir = Directory.current;
      final tempFile = File('${currentDir.path}/$fileName');
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      // Fall through to next method
    }

    try {
      // Method 3: Create file with just the filename (may work in some environments)
      final tempFile = File(fileName);
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      throw Exception('Cannot create temporary file: $e');
    }
  }

  // Fixed alternative method - properly converts Uint8List to File
  Future<String> uploadVideoToSupabaseSimple(
      String bucketName, Uint8List file, String fileName) async {
    try {
      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create temporary file first
      final tempFile = await _createTempFile(uniqueFileName, file);

      // Upload the File object
      final response = await _supabase.storage
          .from(bucketName)
          .upload(uniqueFileName, tempFile);

      await tempFile.delete();

      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(uniqueFileName);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video: $e');
    }
  }

  // Helper method to get video file from gallery
  Future<Uint8List?> pickVideoFromGallery() async {
    try {
      final XFile? videoFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (videoFile != null) {
        return await videoFile.readAsBytes();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick video: $e');
    }
  }

  // Alternative: Get video as File instead of Uint8List
  Future<File?> pickVideoFileFromGallery() async {
    try {
      final XFile? videoFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (videoFile != null) {
        return File(videoFile.path);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick video: $e');
    }
  }

  // Upload video from File (simpler method)
  Future<String> uploadVideoFileToSupabase(
      String bucketName, File videoFile, String fileName) async {
    try {
      String extension = fileName.split('.').last;
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Upload the File directly
      final response = await _supabase.storage
          .from(bucketName)
          .upload(uniqueFileName, videoFile);

      final String publicUrl =
          _supabase.storage.from(bucketName).getPublicUrl(uniqueFileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video file: $e');
    }
  }

  // Delete a video from Supabase Storage
  Future<void> deleteVideoFromSupabase(
      String bucketName, String fileName) async {
    try {
      await _supabase.storage.from(bucketName).remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete video from Supabase: $e');
    }
  }

  // Get a signed URL for private videos
  Future<String> getSignedUrlForVideo(String bucketName, String fileName,
      {int expiresIn = 60}) async {
    try {
      final String signedUrl = await _supabase.storage
          .from(bucketName)
          .createSignedUrl(fileName, expiresIn);
      return signedUrl;
    } catch (e) {
      throw Exception('Failed to get signed URL: $e');
    }
  }
}
