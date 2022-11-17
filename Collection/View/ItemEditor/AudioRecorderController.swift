//
//  AudioRecorderController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/10.
//

import AVFoundation
import UIKit

class AudioRecorderController: UIViewController {

    enum State {
        case readyToRecord
        case recording
        case readyToPlay
        case playing

        var buttonImage: UIImage? {
            switch self {
            case .readyToRecord:
                return UIImage(systemName: "record.circle")
            case .recording:
                return UIImage(systemName: "stop.circle.fill")
            case .readyToPlay:
                return UIImage(systemName: "play.circle.fill")
            case .playing:
                return UIImage(systemName: "stop.circle.fill")
            }
        }
    }

    @IBOutlet var titleTextField: UITextField!
    @IBOutlet var timerLebel: UILabel!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var saveButton: UIButton!

    private let saveHandler: (Result<AudioRecord, Error>) -> Void

    private var state: State = .readyToRecord {
        didSet {
            recordButton.setImage(state.buttonImage, for: .normal)
            resetButton.isEnabled = state == .readyToPlay
            saveButton.isEnabled = state == .playing || state == .readyToPlay
        }
    }

    private let session = AVAudioSession.sharedInstance()

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var newRecord: AudioRecord?

    private lazy var recordURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("m4a")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configure()
    }

    init?(coder: NSCoder, saveHandler: @escaping (Result<AudioRecord, Error>) -> Void) {
        self.saveHandler = saveHandler
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configure() {
        saveButton.isEnabled = false
        resetButton.isEnabled = false
        resetTimerLabel()

        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: recordURL, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()

            self.recorder = recorder
        } catch {
            print("#\(#function): Failed to record sound, \(error)")
        }
    }

    private func configurePlayer() {
        guard
            let recorder = recorder,
            let player = try? AVAudioPlayer(contentsOf: recorder.url)
        else {
            print("#\(#function): Failed to initialize and prepare AVAudioPlayer")
            return
        }

        player.delegate = self
        player.prepareToPlay()

        self.player = player
    }

    private func startRecording() {
        recorder?.record()
        state = .recording

        startTimer()
    }

    private func stopRecording() {
        recorder?.stop()
        timer?.invalidate()
        state = .readyToPlay

        configurePlayer()
    }

    private func startPlaying() {
        player?.play()
        state = .playing

        resetTimerLabel()
        startTimer()
    }

    private func stopPlaying() {
        player?.stop()
        timer?.invalidate()
        state = .readyToPlay
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {[weak self] timer in
            guard let `self` = self else {
                timer.invalidate()
                return
            }

            var timeInterval: TimeInterval = 0

            if self.state == .recording {
                guard
                    let recorder = self.recorder,
                    recorder.isRecording
                else {
                    timer.invalidate()
                    return
                }

                timeInterval = recorder.currentTime
            } else if self.state == .playing {
                guard
                    let player = self.player,
                    player.isPlaying
                else {
                    timer.invalidate()
                    return
                }

                timeInterval = player.currentTime
            } else {
                timer.invalidate()
                return
            }

            let formatter = DateComponentsFormatter.audioDurationFormatter
            if let duration = formatter.string(from: timeInterval) {
                self.timerLebel.text = duration
            }
        }

        timer?.fire()
    }

    private func resetTimerLabel() {
        timerLebel.text = "00:00"
    }

    // MARK: - Actions

    @IBAction func recordButtonTapped() {
        switch state {
        case .readyToRecord:
            startRecording()
        case .recording:
            stopRecording()
        case .readyToPlay:
            startPlaying()
        case .playing:
            stopPlaying()
        }
    }

    @IBAction func resetButtonTapped() {
        recorder?.deleteRecording()
        resetTimerLabel()
        timer?.invalidate()
        recorder?.prepareToRecord()

        state = .readyToRecord
    }

    @IBAction func cancelButtonTapped() {
        self.dismiss(animated: true)
    }

    @IBAction func saveButtonTapped() {
        if state == .playing {
            stopPlaying()
        }

        var audioRecord = AudioRecord(name: nil, url: recordURL, duration: player?.duration)

        if let title = titleTextField.text, !title.isEmpty {
            audioRecord.name = title
        }

        saveHandler(.success(audioRecord))
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderController: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            state = .readyToPlay
        }
    }
}

extension AudioRecorderController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlaying()
    }
}
