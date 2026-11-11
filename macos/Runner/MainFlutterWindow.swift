import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    // L'iPod flotte seul : fenêtre et vue Flutter transparentes dès le départ
    // (avant que Dart n'enlève la barre de titre), sans cadre qui clignote.
    flutterViewController.backgroundColor = .clear
    self.isOpaque = false
    self.backgroundColor = .clear
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
