import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// iPadOS 26 draws window controls in the top-leading corner. Flutter
  /// cannot see that region, so by default they sit on top of each screen's
  /// back button and throw the header row out of line. The minimal style
  /// keeps them in a slim strip of their own above the app.
  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    .minimal
  }
}
