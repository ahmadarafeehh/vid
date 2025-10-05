import UIKit
import Flutter
import video_thumbnail

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var videoThumbnailRegistered = false
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 1. First register ALL other plugins normally
    GeneratedPluginRegistrant.register(with: self)
    
    // 2. Delay video_thumbnail registration specifically
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.safelyRegisterVideoThumbnail()
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func safelyRegisterVideoThumbnail() {
    guard !videoThumbnailRegistered else { return }
    
    // Use the existing engine, don't create a new one
    if let registrar = registrar(forPlugin: "VideoThumbnailPlugin") {
        VideoThumbnailPlugin.register(with: registrar)
        videoThumbnailRegistered = true
        print("✅ VideoThumbnailPlugin registered successfully with delay")
    } else {
        print("⚠️ Failed to get registrar, retrying...")
        // One more try with longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let registrar = self.registrar(forPlugin: "VideoThumbnailPlugin") {
                VideoThumbnailPlugin.register(with: registrar)
                self.videoThumbnailRegistered = true
                print("✅ VideoThumbnailPlugin registered on second attempt")
            }
        }
    }
  }
}
