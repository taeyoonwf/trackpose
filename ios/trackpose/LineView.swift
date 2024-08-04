//
//  LineView.swift
//  trackpose
//
//  Created by Taeyoon Lee on 8/4/24.
//

import Foundation
import UIKit

class LineView: UIView {

  var firstLineStart: CGPoint = CGPoint(x: 20, y: 20)
  var firstLineEnd: CGPoint = CGPoint(x: 280, y: 20)

  var secondLineStart: CGPoint = CGPoint(x: 20, y: 40)
  var secondLineEnd: CGPoint = CGPoint(x: 280, y: 40)

  let lineAlpha: CGFloat = 0.75
  var height: CGFloat? // = 200
  var gapMult: CGFloat? // = 150
  
  override init(frame: CGRect) { // 320x548 -> 75
    super.init(frame: frame)
    print(frame)
    self.height = frame.height * 0.35
    self.gapMult = frame.height * 0.15
    self.backgroundColor = .clear // 768x1004 -> 150
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.backgroundColor = .clear
  }
  
  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    
    context.setLineWidth(4.0)
    context.setStrokeColor(UIColor.red.withAlphaComponent(lineAlpha).cgColor)
    
    context.move(to: firstLineStart)
    context.addLine(to: firstLineEnd)
    
    context.move(to: secondLineStart)
    context.addLine(to: secondLineEnd)
    
    context.strokePath()
  }
  
  func updateLines(firstStart: CGPoint, firstEnd: CGPoint, secondStart: CGPoint, secondEnd: CGPoint) {
    firstLineStart = firstStart
    firstLineEnd = firstEnd
    secondLineStart = secondStart
    secondLineEnd = secondEnd
    self.setNeedsDisplay()
  }
  
  func updateGap(gap: CGFloat) {
    updateLines(
      firstStart: CGPoint(x: frame.midX - height! * 0.5, y: frame.midY - gap * gapMult!),
      firstEnd: CGPoint(x: frame.midX + height! * 0.5, y: frame.midY - gap * gapMult!),
      secondStart: CGPoint(x: frame.midX - height! * 0.5, y: frame.midY + gap * gapMult!),
      secondEnd: CGPoint(x: frame.midX + height! * 0.5, y: frame.midY + gap * gapMult!))
  }
}
