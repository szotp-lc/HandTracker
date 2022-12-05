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


class HandLandmarkTrackingGpu: NSObject, MediaPipeGraphDelegate {
    struct Output {
        let handLandmarks: [Data]
        let worldLandmarks: [Data]
        let handedness: [Data]
    }

    var receiver = PacketReceiver()
    var graph: MediaPipeGraph?
    
    var lastSend = Date.distantPast
    var minimumTimeInterval = 0.15
    
    func run(handler: @escaping (Output) -> Void) throws {
        let url = Bundle(for: MediaPipeGraph.self).url(forResource: "hand_landmark_tracking_gpu", withExtension: "binarypb")!
        
        let graph = try MediaPipeGraph(binaryGraphConfig: Data(contentsOf: url))
        
        graph.setSidePacket(.init(int32: 2), named: "num_hands")
        graph.setSidePacket(.init(int32: 1), named: "model_complexity")
        graph.setSidePacket(.init(bool: true), named: "use_prev_landmarks")
        
        graph.addFrameOutputStream("multi_hand_landmarks", outputPacketType: .raw)
        graph.addFrameOutputStream("multi_hand_world_landmarks", outputPacketType: .raw)
        graph.addFrameOutputStream("multi_handedness", outputPacketType: .raw)
        graph.delegate = receiver
        receiver.handler = { batch in
            handler(Output(
                handLandmarks: batch.packets["multi_hand_landmarks"]?.getArrayOfProtos() ?? [],
                worldLandmarks: batch.packets["multi_hand_world_landmarks"]?.getArrayOfProtos() ?? [],
                handedness: batch.packets["multi_handedness"]?.getArrayOfProtos() ?? [])
            )
        }
        
        try graph.start()
        self.graph = graph
    }
    
    func send(buffer: CVPixelBuffer) {
        let now = Date()
        if now.timeIntervalSince(lastSend) < minimumTimeInterval {
            return
        }
        lastSend = now
        graph?.send(buffer, intoStream: "image", packetType: .pixelBuffer)
    }
}

class PacketReceiver: NSObject, MediaPipeGraphDelegate {
    struct Batch {
        var timestamp: MediaPipeTimestamp
        var packets: [String: MediaPipePacket]
    }
    
    var handler: ((Batch) -> Void)?
    
    var batch: Batch?
    
    let syncQueue = DispatchQueue(label: "PacketReceiver")
    
    func mediapipeGraph(_ graph: MediaPipeGraph, didOutputPacket packet: MediaPipePacket, fromStream streamName: String) {
        syncQueue.async {
            if let batch = self.batch, batch.timestamp != packet.timestamp {
                let currentBatch = batch
                self.batch = nil
                DispatchQueue.main.async {
                    self.handler?(currentBatch)
                }
            }
            
            if self.batch == nil {
                self.batch = .init(timestamp: packet.timestamp, packets: [:])
            }
            
            self.batch?.packets[streamName] = packet
        }
    }
}

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, MediaPipeGraphDelegate {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var toggleView: UISwitch!
    let camera = Camera()
    
    let tracker = HandLandmarkTrackingGpu()

    override func viewDidLoad() {
        super.viewDidLoad()
        camera.setSampleBufferDelegate(self)
        camera.start()

        try! tracker.run { (output) in
            print(output.worldLandmarks.count)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        tracker.send(buffer: pixelBuffer)
        
        DispatchQueue.main.async {
            if !self.toggleView.isOn {
                self.imageView.image = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
            }
        }
    }
}
