//
//  StreamSync.swift
//  trackpose
//
//  Created by Taeyoon Lee on 8/1/24.
//

import Foundation
import UIKit

class StreamSync {
  
  // MARK: Types
  public enum Action {
    case PASS
    case CONT
  }
  
  // MARK: Initialization
  private let STABLE_THRESHOLD: Int = 15
  public let TIME_OUT_MS: Int = 16
  private let DISCONNECT_THRESHOLD: CGFloat = 1.0
  private let MIN_TIMESTAMP: Int64 = Int64(17 * 1e11)

  private var curr_frame: String?
  private var curr_pub_time: Int64?

  private var curr_sub_time: Int64?
  private var last_pub_time: Int64?
  private var last_sub_time: Int64?
  private var pub_sub_diff: Int64?
  private var pub_sub_diff_stable: Int = 0
  private var time_out_counter: Int = 0
  
  public let loading_frame: UIImage = UIImage(color: .black)!
  //private var regionOfInterestControlRadius: CGFloat {
  //  return regionOfInterestControlDiameter / 2.0
  //}

  func no_poll_in_data() -> (Action, UIImage?) {
    time_out_counter += 1
    if CGFloat(time_out_counter) > CGFloat(DISCONNECT_THRESHOLD * 1000.0) / CGFloat(TIME_OUT_MS) {
      return (Action.PASS, loading_frame)
    }
    return (Action.CONT, nil)
  }
  
  func update(timestamp: Int64, frame: String) -> (Action, UIImage?) {
    let curr_pub_time = timestamp
    self.curr_pub_time = timestamp
    curr_frame = frame
    time_out_counter = 0
    if curr_pub_time < MIN_TIMESTAMP {
      print("the timestamp of the pub is too much earlier than expected")
      return (Action.CONT, nil)
    }
    
    let curr_sub_time = Int64(NSDate().timeIntervalSince1970 * 1000)
    self.curr_sub_time = curr_sub_time
    let curr_pub_sub_diff = curr_sub_time - curr_pub_time
    if self.last_pub_time == nil {
      last_pub_time = curr_pub_time
      last_sub_time = curr_sub_time
      pub_sub_diff = curr_pub_sub_diff
      return (Action.CONT, nil)
    }
    
    let delta_time = curr_pub_time - last_pub_time!
    if curr_pub_sub_diff < pub_sub_diff! {
      if curr_pub_sub_diff < pub_sub_diff! - delta_time / 2 {
        last_pub_time = curr_pub_time
        last_sub_time = curr_sub_time
        pub_sub_diff = curr_pub_sub_diff
        return (Action.CONT, nil)
      }
      last_pub_time = curr_pub_time
      last_sub_time = curr_sub_time
      pub_sub_diff = curr_pub_sub_diff
      pub_sub_diff_stable = 0
    } else {
      pub_sub_diff_stable += 1
    }
    
    return (Action.PASS, nil)
  }
  
  func render() -> (Action, UIImage?) {
    last_pub_time = curr_pub_time
    last_sub_time = curr_sub_time
    if pub_sub_diff_stable < STABLE_THRESHOLD {
      return (Action.CONT, nil)
    }

    let imageData = Data(base64Encoded: curr_frame!)
    let image = UIImage(data: imageData!)
    let lsimage = UIImage(cgImage: image!.cgImage!, scale: 1, orientation: UIImage.Orientation.right)
    return (Action.PASS, lsimage)
  }
}

public extension UIImage {
  convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
    let rect = CGRect(origin: .zero, size: size)
    UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
    color.setFill()
    UIRectFill(rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
        
    guard let cgImage = image?.cgImage else { return nil }
    self.init(cgImage: cgImage)
  }
}
