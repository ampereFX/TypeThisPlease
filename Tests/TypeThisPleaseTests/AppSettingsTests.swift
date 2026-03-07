import Foundation
import Testing
@testable import TypeThisPlease

struct AppSettingsTests {
    @Test
    func decodesOlderSettingsPayloadWithoutLosingWhisperConfiguration() throws {
        let legacyJSON = """
        {
          "recordingHotKey": {
            "keyCode": 41,
            "modifiers": 9
          },
          "checkpointHotKey": {
            "keyCode": 39,
            "modifiers": 9
          },
          "outputAction": "copyAndPaste",
          "devicePreferences": [
            {
              "uid": "device-1",
              "name": "Studio Mic"
            }
          ],
          "preferredEngineID": "whisper.cpp",
          "whisperConfiguration": {
            "executablePath": "/tmp/whisper-cli",
            "modelPath": "/tmp/model.bin",
            "runtimeDownloadURL": "",
            "modelDownloadURL": "",
            "language": "de",
            "prompt": "",
            "extraArguments": "--no-prints"
          },
          "hasCompletedOnboarding": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))

        #expect(settings.whisperConfiguration.executablePath == "/tmp/whisper-cli")
        #expect(settings.whisperConfiguration.modelPath == "/tmp/model.bin")
        #expect(settings.outputAction == .copyAndPaste)
        #expect(settings.finalizeBehavior == .reviewBeforeDelivery)
        #expect(settings.devicePreferences.count == 1)
        #expect(settings.hasCompletedOnboarding)
    }
}
