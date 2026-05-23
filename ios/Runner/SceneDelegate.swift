import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let engine = FlutterEngine(name: "main", project: nil)
        engine.run()
        GeneratedPluginRegistrant.register(with: engine)

        let flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let newWindow = UIWindow(windowScene: windowScene)
        newWindow.rootViewController = flutterVC
        newWindow.makeKeyAndVisible()
        self.window = newWindow

        print(">>> SCENE: window created OK")
    }
}
