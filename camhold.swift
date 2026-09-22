// camhold: keep a UVC camera streaming at a chosen low format so that its
// digital pan/tilt/zoom is honored by every other client (Teams, Photo Booth).
//
// The Logitech C925e only applies its zoom/pan crop at stream formats of
// 1024x576 and below; at 1280x720 the crop is ignored and at 1920x1080 it is
// capped at roughly 1.2x. macOS shares one format between all clients of a
// camera, and the most recent client to set a format wins, so this tool holds
// the camera open and re-asserts its format whenever another client changes it.
//
// Usage: camhold [--name C925e] [--size 1024x576] [--verbose]
// Stop with Ctrl-C.

import AVFoundation
import Foundation

var name = "C925e"
var width: Int32 = 1024
var height: Int32 = 576
var verbose = false

var iter = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iter.next() {
	switch arg {
	case "--name": name = iter.next() ?? name
	case "--size":
		let parts = (iter.next() ?? "").split(separator: "x").compactMap { Int32($0) }
		if parts.count == 2 { width = parts[0]; height = parts[1] }
	case "--verbose": verbose = true
	default:
		FileHandle.standardError.write("usage: camhold [--name C925e] [--size 1024x576] [--verbose]\n".data(using: .utf8)!)
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
	init(device: AVCaptureDevice, format: AVCaptureDevice.Format, width: Int32, height: Int32) {
		self.device = device
		self.format = format
		self.width = Int(width)
		self.height = Int(height)
	}
	var lastWidth = 0
	var lastHeight = 0
	var driftSince: Date?

	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		let w = CVPixelBufferGetWidth(pixelBuffer)
		let h = CVPixelBufferGetHeight(pixelBuffer)
		if w != lastWidth || h != lastHeight {
			if lastWidth != 0 { log("stream format changed to \(w)x\(h)") }
			lastWidth = w
			lastHeight = h
		}
		if w == width && h == height {
			driftSince = nil
			return
		}
		// Another client changed the shared format. Give it a moment to settle,
		// then take the format back.
		let now = Date()
		if driftSince == nil { driftSince = now }
		if now.timeIntervalSince(driftSince!) >= 1.0 {
			driftSince = now
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
}

let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: device)
session.addInput(input)
let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = true
let watcher = Watcher(device: device, format: format, width: width, height: height)
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
