import Foundation

enum ModelResourceLocator {
    private static let modelName = "kokoro-v1_0.safetensors"

    static func firstAvailableURL(in bundle: Bundle = .main) -> URL? {
        let extensionResources = bundle.builtInPlugInsURL?
            .appendingPathComponent("KokoroVoiceExtension.appex/Contents/Resources")

        let candidates = [
            extensionResources?.appendingPathComponent("Resources"),
            extensionResources,
            bundle.resourceURL?.appendingPathComponent("Resources"),
            bundle.resourceURL,
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent(modelName).path
            )
        }
    }
}
