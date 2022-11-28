//
//  ViewController.swift
//  Example
//
//  Created by Tomoya Hirano on 2020/04/02.
//  Copyright © 2020 Tomoya Hirano. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPipeHands

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, MediaPipeGraphDelegate {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var toggleView: UISwitch!
    let camera = Camera()
    
    var tracker: MediaPipeGraph?
    
    func setupGraph() throws -> MediaPipeGraph {
        let url = Bundle(for: MediaPipeGraph.self).url(forResource: "hand_tracking_mobile_gpu", withExtension: "binarypb")!
        
        let hands = MediaPipeGraph(graphConfig: try Data(contentsOf: url))
        hands.setSidePacket(.init(number: 2), named: "num_hands")

        hands.delegate = self
        hands.addFrameOutputStream("hand_landmarks", outputPacketType: .raw)
        hands.addFrameOutputStream("output_video", outputPacketType: .pixelBuffer)
        hands.delegate = self
        try hands.start()
        return hands
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        camera.setSampleBufferDelegate(self)
        camera.start()
        
        tracker = try! setupGraph()
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        tracker?.send(pixelBuffer, intoStream: "input_video", packetType: .pixelBuffer)
        
        DispatchQueue.main.async {
            if !self.toggleView.isOn {
                self.imageView.image = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
            }
        }
    }
    
    func mediapipeGraph(_ graph: MediaPipeGraph, didOutputPacket packet: MediaPipePacket, fromStream streamName: String) {
        print(streamName)
    }
    
    func mediapipeGraph(_ graph: MediaPipeGraph, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, fromStream streamName: String, timestamp: MediaPipeTimestamp) {
        DispatchQueue.main.async {
            if self.toggleView.isOn {
                self.imageView.image = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
            }
        }
    }
}
