import AVFoundation
import Speech

/// 语音识别引擎：SFSpeechRecognizer（zh-CN，优先设备端识别）+ AVAudioEngine 取麦。
final class VoiceEngine {
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()
  private(set) var running = false
  private var lastText = ""
  private var deliveredFinal = false

  var onPartial: ((String) -> Void)?
  var onFinal: ((String) -> Void)?
  var onError: ((String) -> Void)?

  // MARK: - 权限

  static func micGranted() -> Bool {
    if #available(macOS 14.0, *) {
      return AVAudioApplication.shared.recordPermission == .granted
    } else {
      return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
  }

  static func requestMic(_ done: @escaping (Bool) -> Void) {
    if #available(macOS 14.0, *) {
      AVAudioApplication.requestRecordPermission { done($0) }
    } else {
      AVCaptureDevice.requestAccess(for: .audio) { done($0) }
    }
  }

  static func speechGranted() -> Bool {
    SFSpeechRecognizer.authorizationStatus() == .authorized
  }

  static func requestSpeech(_ done: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async { done(status == .authorized) }
    }
  }

  /// 依次请求麦克风与语音识别权限。
  static func requestAll(_ done: @escaping (Bool) -> Void) {
    requestMic { micOk in
      requestSpeech { speechOk in
        done(micOk && speechOk)
      }
    }
  }

  // MARK: - 识别

  func start() {
    guard !running else { return }
    guard Self.micGranted() else {
      onError?("未授权麦克风")
      return
    }
    guard Self.speechGranted() else {
      onError?("未授权语音识别")
      return
    }
    let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
    guard let rec, rec.isAvailable else {
      onError?("语音识别暂不可用")
      return
    }
    recognizer = rec
    lastText = ""
    deliveredFinal = false

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    if rec.supportsOnDeviceRecognition {
      req.requiresOnDeviceRecognition = true
    }
    request = req

    let input = audioEngine.inputNode
    input.removeTap(onBus: 0)
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      onError?("麦克风不可用")
      return
    }
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
      req.append(buffer)
    }
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      onError?("麦克风启动失败：\(error.localizedDescription)")
      return
    }
    running = true
    task = rec.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      if let result {
        self.lastText = result.bestTranscription.formattedString
        if result.isFinal {
          self.deliveredFinal = true
          self.finish(with: self.lastText)
        } else {
          self.onPartial?(self.lastText)
        }
      }
      if error != nil && !self.deliveredFinal {
        self.deliveredFinal = true
        self.finish(with: self.lastText)
      }
    }
  }

  func stop() {
    guard running else { return }
    request?.endAudio()
    // endAudio 后最终结果异步回来；600ms 兜底，超时用已知文本收尾。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, self.running || !self.deliveredFinal else { return }
      if !self.deliveredFinal {
        self.deliveredFinal = true
        self.finish(with: self.lastText)
      }
    }
  }

  private func finish(with text: String) {
    teardownEngine()
    onFinal?(text)
  }

  private func teardownEngine() {
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    task?.cancel()
    task = nil
    request = nil
    running = false
  }
}
