import Foundation
#if os(macOS)
import AppKit
public typealias PlatformFont  = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformFont  = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
#endif
