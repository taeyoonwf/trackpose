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
  //var resized: Bool = false
  let streamSync: StreamSync = StreamSync()
  var lineView: LineView?
  
  @IBOutlet private var imageView: UIImageView!
  @IBOutlet private var slider: UISlider! {
    didSet{
      //print(imageView.frame.size)
      slider.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2)).translatedBy(x: 0, y: imageView.frame.size.width / 2 - 30)
      
    }
  }

  @IBAction func updateSlider(_ sender: UISlider) {
    //print(imageView.bounds.)
    //print("sliding now")
    lineView!.updateGap(gap: CGFloat(sender.value))
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    UIApplication.shared.isIdleTimerDisabled = true
    if UIDevice.current.userInterfaceIdiom == .pad {
      //imageView.frame.size = CGSize(width: imageView.frame.width, height: imageView.frame.height - 109)
    } else {
      //imageView.frame.size = CGSize(width: imageView.frame.width, height: imageView.frame.height - 59)
    }
    // Do any additional setup after loading the view.
    lineView = LineView(frame: imageView.bounds)
    imageView.addSubview(lineView!)
    lineView?.updateGap(gap: 0.5)

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
      var bufsize = 1024
      var buffer = [UInt8](repeating: 0, count: bufsize)

      while true {
        let rc = zmq_poll(&pollItems, 1, streamSync.TIME_OUT_MS)

        if rc == -1 {
          print("polling error")
          break
        }

        if pollItems[0].revents & Int16(ZMQ_POLLIN) != 0 {
          let size = zmq_recv(self.subscriber, &buffer, bufsize, 0)
          if size >= bufsize {
            bufsize *= 2
            buffer = [UInt8](repeating: 0, count: bufsize)
          }
          else if size > 0 {
            let message = String(bytes: buffer[..<Int(size)], encoding: .utf8) ?? ""
            DispatchQueue.main.async {
              self.handleMessage(message)
            }
          }
        } else {
          let (cont, image) = streamSync.no_poll_in_data()
          if cont == StreamSync.Action.CONT {
            continue
          }
          DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
              self.imageView.image = image
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

          var (cont, image) = streamSync.update(timestamp: timestamp!, frame: frame!)
          if cont == StreamSync.Action.CONT {
            return
          }
          
          (cont, image) = streamSync.render()
          if cont == StreamSync.Action.CONT {
            return
          }
          
          if UIApplication.shared.applicationState == .active {
            self.imageView.image = image
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
