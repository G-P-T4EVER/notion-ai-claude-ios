import Foundation
import AVFoundation
import Speech

enum DictationError: LocalizedError {
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Allow microphone and speech recognition access in iOS Settings."
        case .unavailable:
            return "Dictation is not available on this device right now."
        }
    }
}

/// Microphone dictation for the composer. On-device when the OS supports it,
/// which keeps it usable on iOS 14 hardware.
final class Dictation {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRecording = false

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            let speechGranted = status == .authorized
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                DispatchQueue.main.async { completion(speechGranted && micGranted) }
            }
        }
    }

    func start(
        onTranscript: @escaping (String) -> Void,
        onLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError(DictationError.unavailable)
            return
        }

        Dictation.requestAuthorization { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                onError(DictationError.unauthorized)
                return
            }

            do {
                try self.beginSession(recognizer: recognizer, onTranscript: onTranscript, onLevel: onLevel, onError: onError)
            } catch {
                onError(error)
            }
        }
    }

    private func beginSession(
        recognizer: SFSpeechRecognizer,
        onTranscript: @escaping (String) -> Void,
        onLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *), recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)

            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<frames {
                sum += channel[index] * channel[index]
            }
            let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
            DispatchQueue.main.async { onLevel(min(1, rms * 12)) }
        }

        engine.prepare()
        try engine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    onTranscript(result.bestTranscription.formattedString)
                }
            }
            if let error = error {
                self?.stop()
                DispatchQueue.main.async { onError(error) }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
