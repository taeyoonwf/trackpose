//
//  ViewController.swift
//  trackpose
//
//  Created by Taeyoon Lee on 7/29/24.
//

import UIKit

class ViewController: UIViewController {

  var context: UnsafeMutableRawPointer?
  var subscriber: UnsafeMutableRawPointer?
  let queue = DispatchQueue(label: "com.yourapp.zeromq", qos: .background)
  var resized: Bool = false

  @IBOutlet private var imageView: UIImageView!

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.

    context = zmq_ctx_new()
    subscriber = zmq_socket(context, ZMQ_SUB)

    // Connect to the ZeroMQ server
    zmq_bind(subscriber, "tcp://*:5555")
    //zmq_connect(subscriber, "tcp://*:5555")

    // Subscribe to all messages
    //let empty: NSString = ""
    //var empty_p = UnsafePointer<CChar>(empty.utf8String)
    //zmq_setsockopt(subscriber, ZMQ_SUBSCRIBE, &empty_p, 0)
    zmq_setsockopt(subscriber, ZMQ_SUBSCRIBE, "", 0)

    // Start listening for messages
    startListening()
  }

  func startListening() {
    queue.async { [weak self] in
      guard let self = self else { return }

      var pollItems = [zmq_pollitem_t(socket: self.subscriber, fd: 0, events: Int16(ZMQ_POLLIN), revents: 0)]
      let bufsize = 65536
      var buffer = [UInt8](repeating: 0, count: bufsize)

      while true {
        let rc = zmq_poll(&pollItems, 1, 8)
            
        if rc == -1 {
          print("polling error")
          break
        }
            
        if pollItems[0].revents & Int16(ZMQ_POLLIN) != 0 {
          let size = zmq_recv(self.subscriber, &buffer, bufsize, 0)
          if size > 0 {
            let message = String(bytes: buffer[..<Int(size)], encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.handleMessage(message)
            }
          }
        }
      }
    }
  }

  func handleMessage(_ message: String) {
      // Handle the received message
      //print("Received message: \(message)")
    if let jsonData = message.data(using: .utf8) {
      do {
        if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
          let frame = json["frame"] as? String
          let timestamp = json["timestamp"] as? Int64
          if frame != nil {
            if let imageData = Data(base64Encoded: frame!) {
              if let image = UIImage(data: imageData) {
                let lsimage = UIImage(cgImage: image.cgImage!, scale: 1, orientation: UIImage.Orientation.right)
                self.imageView.image = lsimage
                //self.imageView.contentMode = .scaleAspectFit //.scaleToFill //.scaleAspectFill//.scaleAspectFit
                print("imageViewFrame : \(self.imageView.frame.width) x \(self.imageView.frame.height)")
                //print("imageCgSize : \(self.imageView.image?.cgImage) x \(self.imageView.image?.cgImage)")
                print("image : \(lsimage.size.width) x \(lsimage.size.height)")
                print("imageViewBounds : \(self.imageView.bounds.size)")
                print("mins \(self.imageView.frame.minX) \(self.imageView.frame.minY) \(self.imageView.frame.maxX) \(self.imageView.frame.maxY) ")
                
                
                if resized == false {
                  var minRatio = min(lsimage.size.width / self.imageView.frame.width, lsimage.size.height / self.imageView.frame.height)
                  //minRatio = 1
                  //self.imageView.layer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeRotation(Double.pi / 2).concatenating(CGAffineTransformMakeScale(1/minRatio, 1/minRatio)))
                  resized = true
                }
                //self.imageView.layer.transform = CATransform3DMakeRotation(90, <#T##x: CGFloat##CGFloat#>, <#T##y: CGFloat##CGFloat#>, <#T##z: CGFloat##CGFloat#>) CGAffineTransformMakeRotation(90)
                //self.imageView.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
              }
            }
          }
        }
      } catch {
        print("failed to parse JSON: \(error.localizedDescription)")
      }
    }
    //var data: NSData = message.dataUsingEncoding(NSUTF8StringEncoding)!
    //print("asdf")
  }

  deinit {
      // Clean up ZeroMQ
      zmq_close(subscriber)
      zmq_ctx_destroy(context)
  }
  

}
