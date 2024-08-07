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
  var ipCheckPeriod: Int = 0
  var ipCheckCounter: Int = 0
  let base36code: String = "1qazxsw23edcvfr45tgbnhy67ujmki89olp0"
  
  @IBOutlet private var imageView: UIImageView!
  @IBOutlet private var slider: UISlider! {
    didSet {
      //print(imageView.frame.width)
      //print(imageView.frame.height)
      //print(slider.frame.width)
      //print(slider.frame.height)
      slider.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2)).translatedBy(x: 0, y: imageView.frame.size.width / 2 - 30)
      
    }
  }
  @IBOutlet private var networkLabel: UILabel! {
    didSet {
      let whDiff = networkLabel.frame.width - networkLabel.frame.height
      networkLabel.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2)).translatedBy(x: whDiff * 0.5 + 8, y: -whDiff * 0.5 + 8)
      //networkLabel.sizeToFit()
      //networkLabel.numberOfLines = 0
    }
  }
  @IBOutlet private var resetNetworkButton: UIButton! {
    didSet {
      let whDiff = resetNetworkButton.frame.width - resetNetworkButton.frame.height
      resetNetworkButton.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2)).translatedBy(x: whDiff * 0.5 + 8, y: -whDiff * 0.5 + 8)
    }
  }
  @IBAction func updateSlider(_ sender: UISlider) {
    //print(imageView.bounds.)
    //print("sliding now")
    lineView!.updateGap(gap: CGFloat(sender.value))
  }
  
  @IBAction func resetNetwork(_ sender: UIButton) {
    print("reset network touched!")
    zmq_close(subscriber)
    zmq_ctx_destroy(context)

    context = zmq_ctx_new()
    subscriber = zmq_socket(context, ZMQ_SUB)
    zmq_bind(subscriber, "tcp://*:5555")
    zmq_setsockopt(subscriber, ZMQ_SUBSCRIBE, "", 0)

    startListening()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    UIApplication.shared.isIdleTimerDisabled = true
    if UIDevice.current.userInterfaceIdiom == .pad {
      //imageView.frame.size = CGSize(width: imageView.frame.width, height: imageView.frame.height - 109)
    } else {
      //imageView.frame.size = CGSize(width: imageView.frame.width, height: imageView.frame.height - 59)
    }
    ipCheckPeriod = 1000 / streamSync.TIME_OUT_MS
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

  func intValueToB36(val: UInt8) -> String {
    if val >= base36code.count {
      assertionFailure()
    }
    let v = base36code.index(base36code.startIndex, offsetBy: Int(val))
    let chr = base36code[v]
    return String(chr)
  }

  func threeNumbersToStr(num0: UInt8, num1: UInt8, num2: UInt8) -> String {
    let s0: UInt8 = (num0 << 3) | ((num1 & 224) >> 5)
    let s1: UInt8 = (num1 & 31)
    let s2: UInt8 = (num2 & 240) >> 4
    let s3: UInt8 = (num2 & 15)

    return intValueToB36(val: s0) + intValueToB36(val: s1) + intValueToB36(val: s2) + intValueToB36(val: s3)
  }

  func startListening() {
    queue.async { [weak self] in
      guard let self = self else { return }

      var pollItems = [zmq_pollitem_t(socket: self.subscriber, fd: 0, events: Int16(ZMQ_POLLIN), revents: 0)]
      var bufsize = 1024
      var buffer = [UInt8](repeating: 0, count: bufsize)

      while true {
        let rc = zmq_poll(&pollItems, 1, streamSync.TIME_OUT_MS)
        ipCheckCounter += 1
        if ipCheckCounter == ipCheckPeriod {
          ipCheckCounter = 0
          let currIp = getWiFiAddress()
          //print(currIp)
          if currIp != nil {
            let ipAry = currIp!.components(separatedBy: ".")
            // let ipStr = "\(ipAry[0]).\(ipAry[1]).\(ipAry[2]).\(ipAry[3])"
            if ipAry[0] == "192" && ipAry[1] == "168" {
              DispatchQueue.main.async {
                self.networkLabel.text = self.threeNumbersToStr(num0: 2, num1: UInt8(ipAry[2])!, num2: UInt8(ipAry[3])!)
              }
            }
          }
        }

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
  
  func getWiFiAddress() -> String? {
      var address : String?

      // Get list of all interfaces on the local machine:
      var ifaddr : UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&ifaddr) == 0 else { return nil }
      guard let firstAddr = ifaddr else { return nil }

      // For each interface ...
      for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
          let interface = ifptr.pointee

          // Check for IPv4 or IPv6 interface:
          let addrFamily = interface.ifa_addr.pointee.sa_family
          if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

              // Check interface name:
              let name = String(cString: interface.ifa_name)
              if  name == "en0" {

                  // Convert interface address to a human readable string:
                  var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                  getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, socklen_t(0), NI_NUMERICHOST)
                  address = String(cString: hostname)
              }
          }
      }
      freeifaddrs(ifaddr)

      return address
  }
}
