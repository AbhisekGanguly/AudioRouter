import Accelerate
import CoreAudio
import Foundation
import os.log

/// One active app→device route: a process tap wrapped in a private aggregate
/// device whose real sub-device is the destination, with an IOProc that copies
/// the tapped audio into the destination's output buffers.
///
/// Uses `.mutedWhenTapped` so the app's normal output is silenced only while
/// this route is actively pulling audio — if we crash, coreaudiod should
/// restore normal playback (and `OrphanedTapCleanup` covers the cases where
/// it doesn't).
final class ProcessTapController {
    /// UID prefix for our private aggregates; OrphanedTapCleanup keys off this.
    static let aggregateUIDPrefix = "com.abhisekganguly.AudioRouter.aggregate."

    let bundleID: String
    let deviceUID: String
    let processObjectIDs: Set<AudioObjectID>

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let queue: DispatchQueue
    private(set) var isActive = false

    /// Written on the main thread, read on the audio IO thread each callback.
    /// Aligned 32-bit loads/stores don't tear on Apple hardware, so a plain
    /// var is safe here without taking a lock in the realtime path.
    private final class VolumeBox {
        var value: Float = 1.0
    }

    private let volumeBox = VolumeBox()

    var volume: Float {
        get { volumeBox.value }
        set { volumeBox.value = min(max(newValue, 0), 1) }
    }

    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "ProcessTapController")

    init(bundleID: String, deviceUID: String, processObjectIDs: Set<AudioObjectID>) {
        self.bundleID = bundleID
        self.deviceUID = deviceUID
        self.processObjectIDs = processObjectIDs
        self.queue = DispatchQueue(label: "AudioRouter.io.\(bundleID)", qos: .userInteractive)
    }

    deinit {
        invalidate()
    }

    func activate() throws {
        guard !isActive else { return }

        // 1. Process tap over all of the app's audio-emitting processes.
        let description = CATapDescription(stereoMixdownOfProcesses: Array(processObjectIDs))
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.name = "AudioRouter tap: \(bundleID)"
        description.isPrivate = true
        description.isExclusive = false

        var newTapID = AudioObjectID.unknown
        try checkOSStatus(
            AudioHardwareCreateProcessTap(description, &newTapID),
            "AudioHardwareCreateProcessTap(\(bundleID))"
        )
        tapID = newTapID

        // 2. Private aggregate: destination device as the only sub-device,
        //    our tap in the tap list.
        let aggregateUID = Self.aggregateUIDPrefix + UUID().uuidString
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter-\(bundleID)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: deviceUID,
                    kAudioSubDeviceDriftCompensationKey: 1,
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: 1,
                ]
            ],
        ]

        var newAggregateID = AudioObjectID.unknown
        do {
            try checkOSStatus(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID),
                "AudioHardwareCreateAggregateDevice(\(bundleID) → \(deviceUID))"
            )
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
            throw error
        }
        aggregateID = newAggregateID

        // 3. IOProc: tap audio arrives as input, destination hardware plays
        //    whatever we write to the output buffers.
        do {
            var newProcID: AudioDeviceIOProcID?
            let volumeBox = self.volumeBox
            try checkOSStatus(
                AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateID, queue) { _, inInputData, _, outOutputData, _ in
                    Self.copyBuffers(from: inInputData, to: outOutputData, gain: volumeBox.value)
                },
                "AudioDeviceCreateIOProcIDWithBlock(\(bundleID))"
            )
            ioProcID = newProcID

            try checkOSStatus(
                AudioDeviceStart(aggregateID, ioProcID),
                "AudioDeviceStart(\(bundleID))"
            )
        } catch {
            invalidate()
            throw error
        }

        isActive = true
        Self.log.info("Route active: \(self.bundleID, privacy: .public) → \(self.deviceUID, privacy: .public)")
    }

    /// Teardown order matters: stop → destroy IOProc → destroy aggregate → destroy tap.
    func invalidate() {
        if let procID = ioProcID, aggregateID.isValid {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
        if isActive {
            Self.log.info("Route torn down: \(self.bundleID, privacy: .public)")
        }
        isActive = false
    }

    /// Copies each input (tap) buffer into the matching output buffer with the
    /// per-app gain applied, zero-filling any remainder so stale samples never
    /// play. Buffers are Float32 (the HAL's canonical format).
    private static func copyBuffers(
        from inInputData: UnsafePointer<AudioBufferList>,
        to outOutputData: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        let output = UnsafeMutableAudioBufferListPointer(outOutputData)

        for index in 0..<output.count {
            guard let dst = output[index].mData else { continue }
            let dstBytes = Int(output[index].mDataByteSize)

            if index < input.count, let src = input[index].mData {
                let copied = min(Int(input[index].mDataByteSize), dstBytes)
                if gain >= 0.999 {
                    memcpy(dst, src, copied)
                } else if gain <= 0.001 {
                    memset(dst, 0, copied)
                } else {
                    var scale = gain
                    let sampleCount = copied / MemoryLayout<Float>.size
                    vDSP_vsmul(
                        src.assumingMemoryBound(to: Float.self), 1,
                        &scale,
                        dst.assumingMemoryBound(to: Float.self), 1,
                        vDSP_Length(sampleCount)
                    )
                }
                if copied < dstBytes {
                    memset(dst.advanced(by: copied), 0, dstBytes - copied)
                }
            } else {
                memset(dst, 0, dstBytes)
            }
        }
    }
}
