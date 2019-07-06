//
//  CameraSessionController.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import CoreImage

@objc protocol CameraSessionControllerDelegate {
	@objc optional func cameraSessionDidOutputSampleBuffer(sampleBuffer: CMSampleBuffer!)
}

class CameraSessionController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	
	var session: AVCaptureSession!
	var sessionQueue: DispatchQueue!
	var videoDeviceInput: AVCaptureDeviceInput!
	var videoDeviceOutput: AVCaptureVideoDataOutput!
	var runtimeErrorHandlingObserver: Any!
	
	var sessionDelegate: CameraSessionControllerDelegate?
	
	
	/* Class Methods
	------------------------------------------*/
	
    class func getCaptureDevice() -> AVCaptureDevice {
        var cameraDevice: AVCaptureDevice?
        
        let cameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back)
        for device in cameraDevices.devices {
            if device.position == .back {
                cameraDevice = device
                break
            }
        }
        return cameraDevice!
    }
	
	
	/* Lifecycle
	------------------------------------------*/
	
    override init() {
		super.init();
		
		session = AVCaptureSession()
		
        session.sessionPreset = AVCaptureSession.Preset.medium
		
		authorizeCamera();
		
        sessionQueue = DispatchQueue(label:"CameraSessionController Session")
		
        sessionQueue.async {
			self.session.beginConfiguration()
			self.addVideoInput()
			self.addVideoOutput()
			self.session.commitConfiguration()
		}
	}
	
	
	/* Instance Methods
	------------------------------------------*/
	
	func authorizeCamera() {
        AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: {
			(granted: Bool) -> Void in
			// If permission hasn't been granted, notify the user.
			if !granted {
				DispatchQueue.main.async {
					UIAlertView(
						title: "Could not use camera!",
						message: "This application does not have permission to use camera. Please update your privacy settings.",
						delegate: self,
						cancelButtonTitle: "OK").show()
					}
			}
		});
	}
	
	func addVideoInput() {
        let videoDevice: AVCaptureDevice = CameraSessionController.getCaptureDevice()
        videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) as AVCaptureDeviceInput;
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        }
	}
	
	func addVideoOutput() {
		videoDeviceOutput = AVCaptureVideoDataOutput()
		videoDeviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
		videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
		videoDeviceOutput.setSampleBufferDelegate(self, queue: sessionQueue)
		if session.canAddOutput(videoDeviceOutput) {
			session.addOutput(videoDeviceOutput)
		}
	}

    func startCamera() {
        sessionQueue.async {
            let weakSelf: CameraSessionController? = self
            self.runtimeErrorHandlingObserver =
                NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureSessionRuntimeError, object: self.sessionQueue, queue: nil, using: {
                    (note: Notification!) -> Void in
                
                    let strongSelf: CameraSessionController = weakSelf!
                
                    strongSelf.sessionQueue.async {
                        strongSelf.session.startRunning()
                    }
				})
			self.session.startRunning()
		}
	}
	
	func teardownCamera() {
		sessionQueue.async {
			self.session.stopRunning()
			NotificationCenter.default.removeObserver(self.runtimeErrorHandlingObserver!)
		}
	}

	
	
	/* AVCaptureVideoDataOutput Delegate
	------------------------------------------*/
	
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if (connection.isVideoOrientationSupported){
            //connection.videoOrientation = AVCaptureVideoOrientation.portraitUpsideDown
            connection.videoOrientation = AVCaptureVideoOrientation.portrait
		}
        if (connection.isVideoMirroringSupported) {
			//connection.videoMirrored = true
            connection.isVideoMirrored = false
		}
        sessionDelegate?.cameraSessionDidOutputSampleBuffer?(sampleBuffer: sampleBuffer)
	}
	
}
