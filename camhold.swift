// camhold: keep a UVC camera streaming at a chosen low format so that its
// digital pan/tilt/zoom is honored by every other client (Teams, Photo Booth).
//
// The Logitech C925e only applies its zoom/pan crop at stream formats of
// 1024x576 and below; at 1280x720 the crop is ignored and at 1920x1080 it is
// capped at roughly 1.2x. macOS shares one format between all clients of a
// camera, and the most recent client to set a format wins, so this tool holds
// the camera open and re-asserts its format whenever another client changes it.
//
// Every moment the format is wrong is visible to everyone in the call as the
// picture panning out to the uncropped view and back, so the format is taken
// back as soon as the drift is confirmed. Repeated attempts back off, so a
// client that keeps insisting on its own format makes the picture settle on
// the wrong size rather than strobe between the two.
//
// Usage: camhold [--name C925e] [--size 1024x576] [--settle 0.05]
//                [--retry 0.2] [--verbose]
// Stop with Ctrl-C.

import AVFoundation
import Foundation

var name = "C925e"
var width: Int32 = 1024
var height: Int32 = 576
// How long an off-size stream must persist before the format is taken back.
// This is the visible length of the glitch, so it is kept to about two frames
// — just enough not to chase a single anomalous buffer.
var settle = 0.05
// Spacing before a second attempt, doubling up to maxRetry for as long as the
// format keeps coming back wrong.
var retry = 0.2
let maxRetry = 2.0
var verbose = false

func parseInterval(_ raw: String?, _ flag: String) -> Double {
	guard let raw, let value = Double(raw), value >= 0, value.isFinite else {
		FileHandle.standardError.write("camhold: \(flag) needs a non-negative number of seconds\n".data(using: .utf8)!)
		exit(1)
	}
	return value
}

var iter = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iter.next() {
	switch arg {
	case "--name": name = iter.next() ?? name
	case "--size":
		let parts = (iter.next() ?? "").split(separator: "x").compactMap { Int32($0) }
		if parts.count == 2 { width = parts[0]; height = parts[1] }
	case "--settle": settle = parseInterval(iter.next(), "--settle")
	case "--retry": retry = parseInterval(iter.next(), "--retry")
	case "--verbose": verbose = true
	default:
		FileHandle.standardError.write("usage: camhold [--name C925e] [--size 1024x576] [--settle 0.05] [--retry 0.2] [--verbose]\n".data(using: .utf8)!)
		exit(1)
	}
}

func log(_ s: String) {
	FileHandle.standardError.write("camhold: \(s)\n".data(using: .utf8)!)
}

let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
guard let device = devices.first(where: { $0.localizedName.contains(name) }) else {
	log("no camera matching \"\(name)\" (found: \(devices.map { $0.localizedName }))")
	exit(2)
}

let access = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .video) { ok in granted = ok; access.signal() }
access.wait()
guard granted else { log("camera access denied"); exit(3) }

guard let format = device.formats.first(where: {
	let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
	return d.width == width && d.height == height
}) else {
	log("\(device.localizedName) has no \(width)x\(height) format")
	exit(4)
}

final class Watcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	let device: AVCaptureDevice
	let format: AVCaptureDevice.Format
	let width: Int
	let height: Int
	let settle: TimeInterval
	let retry: TimeInterval
	let maxRetry: TimeInterval
	init(device: AVCaptureDevice, format: AVCaptureDevice.Format, width: Int32, height: Int32, settle: TimeInterval, retry: TimeInterval, maxRetry: TimeInterval) {
		self.device = device
		self.format = format
		self.width = Int(width)
		self.height = Int(height)
		self.settle = settle
		self.retry = retry
		self.maxRetry = maxRetry
		self.backoff = retry
	}
	var lastWidth = 0
	var lastHeight = 0
	// When the stream was first seen at the wrong size, and when the format was
	// last written back. Both are cleared once the stream is correct again.
	var driftSince: Date?
	var lastAttempt: Date?
	var backoff: TimeInterval

	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		let w = CVPixelBufferGetWidth(pixelBuffer)
		let h = CVPixelBufferGetHeight(pixelBuffer)
		let now = Date()
		if w != lastWidth || h != lastHeight {
			if lastWidth != 0 { log("stream format changed to \(w)x\(h)") }
			lastWidth = w
			lastHeight = h
		}
		if w == width && h == height {
			if let since = driftSince {
				log(String(format: "back to %dx%d after %.0f ms", width, height, now.timeIntervalSince(since) * 1000))
			}
			driftSince = nil
			lastAttempt = nil
			backoff = retry
			return
		}
		// Another client changed the shared format. Confirm the drift across a
		// frame or two, then take the format back.
		guard let since = driftSince else {
			driftSince = now
			return
		}
		let waited = now.timeIntervalSince(lastAttempt ?? since)
		guard waited >= (lastAttempt == nil ? settle : backoff) else { return }
		lastAttempt = now
		backoff = min(backoff * 2, maxRetry)
		do {
			try device.lockForConfiguration()
			device.activeFormat = format
			device.unlockForConfiguration()
			log("re-asserted \(width)x\(height)")
		} catch {
			log("could not re-assert format: \(error)")
		}
	}
}

let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: device)
session.addInput(input)
let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = true
let watcher = Watcher(device: device, format: format, width: width, height: height, settle: settle, retry: retry, maxRetry: maxRetry)
output.setSampleBufferDelegate(watcher, queue: DispatchQueue(label: "camhold"))
session.addOutput(output)
session.startRunning()
Thread.sleep(forTimeInterval: 0.5)
try device.lockForConfiguration()
device.activeFormat = format
device.unlockForConfiguration()
log("holding \(device.localizedName) at \(width)x\(height); Ctrl-C to stop")

signal(SIGINT) { _ in
	log("stopping")
	exit(0)
}
signal(SIGTERM) { _ in exit(0) }
RunLoop.main.run()
