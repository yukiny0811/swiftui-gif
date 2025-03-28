import SwiftUI

public struct GIFImage: UIViewRepresentable {
  private let data: Data?
  private let name: String?
  private let repetitions: Int?
  private let bundle: Bundle
  private let onComplete: (() -> Void)?
  
  public init(
    data: Data,
    repetitions: Int? = nil,
    bundle: Bundle = .main,
    onComplete: (() -> Void)? = nil
  ) {
    self.data = data
    self.name = nil
    self.repetitions = repetitions
    self.bundle = bundle
    self.onComplete = onComplete
  }
  
  public init(
    name: String,
    repetitions: Int? = nil,
    bundle: Bundle = .main,
    onComplete: (() -> Void)? = nil
  ) {
    self.data = nil
    self.name = name
    self.repetitions = repetitions
    self.bundle = bundle
    self.onComplete = onComplete
  }
  
  public func makeUIView(context: Context) -> UIGIFImage {
    if let data = data {
      return UIGIFImage(data: data, repetitions: repetitions, onComplete: onComplete)
    } else {
      return UIGIFImage(name: name ?? "", repetitions: repetitions, onComplete: onComplete)
    }
  }
  
  public func updateUIView(_ uiView: UIGIFImage, context: Context) {
    if let data = data {
      uiView.updateGIF(data: data, repetitions: repetitions, onComplete: onComplete)
    } else {
      uiView.updateGIF(name: name ?? "", repetitions: repetitions, bundle: bundle,  onComplete: onComplete)
    }
  }
}

public struct AnimationImages {
  let frames: [UIImage]
  let duration: Double
}

public class UIGIFImage: UIView {
  private let imageView = UIImageView()
  private var repetitions: Int? = nil
  private var onComplete: (() -> Void)? = nil
  private var data: Data?
  private var name: String?
  
  
  override init(frame: CGRect) {
    super.init(frame: frame)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  convenience init(
    name: String,
    repetitions: Int? = nil,
    onComplete: (() -> Void)? = nil
  ) {
    self.init()
    self.name = name
    initView()
  }
  
  convenience init(
    data: Data,
    repetitions: Int? = nil,
    onComplete: (() -> Void)? = nil
  ) {
    self.init()
    self.data = data
    initView()
  }
  
  public override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
    self.addSubview(imageView)
  }
  
  func updateGIF(
    data: Data,
    repetitions: Int? = nil,
    onComplete: (() -> Void)? = nil
  ) {
    self.repetitions = repetitions
    self.onComplete = onComplete
    updateWithImage {
      UIImage.gifImage(data: data)
    }
  }
  
  func updateGIF(
    name: String,
    repetitions: Int? = nil,
    bundle: Bundle,
    onComplete: (() -> Void)? = nil
  ) {
    self.repetitions = repetitions
    self.onComplete = onComplete
    updateWithImage {
      UIImage.gifImage(name: name, bundle: bundle)
    }
  }
  
  private func updateWithImage(_ getImage: @escaping () -> AnimationImages?) {
    DispatchQueue.global(qos: .userInteractive).async {
      if let animationImages = getImage() {
        DispatchQueue.main.async {
          CATransaction.begin()
          CATransaction.setCompletionBlock {
            self.onComplete?()
          }
          self.imageView.animationImages = animationImages.frames
          self.imageView.animationDuration = animationImages.duration
          self.imageView.animationRepeatCount = self.repetitions ?? Int.max
          self.imageView.startAnimating()
          CATransaction.commit()
        }
      } else {
        self.imageView.image = nil
      }
    }
  }
  
  private func initView(
    repetitions: Int? = nil,
    onComplete: (() -> Void)? = nil
  ) {
    imageView.contentMode = .scaleAspectFit
    self.repetitions = repetitions
    self.onComplete = onComplete
  }
}

public extension UIImage {
    class func gifImage(data: Data) -> AnimationImages? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        let delays = (0..<count).map {
            // store in ms and truncate to compute GCD more easily
            Int(delayForImage(at: $0, source: source) * 1000)
        }
        let duration = delays.reduce(0, +)
        let gcd = delays.reduce(0, gcd)
        
        var frames = [UIImage]()
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                let frame = UIImage(cgImage: cgImage)
                let frameCount = delays[i] / gcd
                
                for _ in 0..<frameCount {
                    frames.append(frame)
                }
            } else {
                return nil
            }
        }
        
      return AnimationImages(frames: frames, duration: Double(duration) / 1000.0)
//        return UIImage.animatedImage(with: frames,
//                                     duration: Double(duration) / 1000.0)
    }
    
    class func gifImage(name: String, bundle: Bundle) -> AnimationImages? {
        guard let url = bundle.url(forResource: name, withExtension: "gif"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return gifImage(data: data)
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    let absB = abs(b)
    let r = abs(a) % absB
    if r != 0 {
        return gcd(absB, r)
    } else {
        return absB
    }
}

private func delayForImage(at index: Int, source: CGImageSource) -> Double {
  let defaultDelay = 1.0
  
  let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
  let gifPropertiesPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 0)
  defer {
    gifPropertiesPointer.deallocate()
  }
  let unsafePointer = Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()
  if CFDictionaryGetValueIfPresent(cfProperties, unsafePointer, gifPropertiesPointer) == false {
    return defaultDelay
  }
  let gifProperties = unsafeBitCast(gifPropertiesPointer.pointee, to: CFDictionary.self)
  var delayWrapper = unsafeBitCast(CFDictionaryGetValue(gifProperties,
                                                        Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
                                   to: AnyObject.self)
  if delayWrapper.doubleValue == 0 {
    delayWrapper = unsafeBitCast(CFDictionaryGetValue(gifProperties,
                                                      Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
                                 to: AnyObject.self)
  }
  
  if let delay = delayWrapper as? Double,
     delay > 0 {
    return delay
  } else {
    return defaultDelay
  }
}

struct GIFImageTest: View {
  @State private var imageData: Data? = nil
  @State private var isDone = false
  
  var body: some View {
    VStack {
      GIFImage(name: "preview")
        .frame(height: 300)
      if let data = imageData {
        GIFImage(data: data)
          .frame(width: 300)
        if isDone {
          Text("Done")
        } else {
          GIFImage(data: data, repetitions: 2) {
            isDone = true
          }
          .frame(width: 300)
        }
      } else {
        Text("Loading...")
          .onAppear(perform: loadData)
      }
    }
  }
  
  private func loadData() {
    let task = URLSession.shared.dataTask(with: URL(string: "https://github.com/globulus/swiftui-webview/raw/main/Images/preview_macos.gif?raw=true")!) { data, response, error in
      imageData = data
    }
    task.resume()
  }
}

struct GIFImage_Previews: PreviewProvider {
  static var previews: some View {
    GIFImageTest()
  }
}

