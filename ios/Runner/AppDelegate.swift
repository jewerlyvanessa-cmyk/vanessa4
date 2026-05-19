import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    LabelPrintChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

// MARK: - Label print (80×12 mm, sama seperti web)

private enum LabelPrintChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.example.vanessa3/label_print",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "arguments required", details: nil))
        return
      }

      switch call.method {
      case "printLabelPdf":
        guard let name = args["name"] as? String,
              let widthMm = (args["widthMm"] as? NSNumber)?.doubleValue,
              let heightMm = (args["heightMm"] as? NSNumber)?.doubleValue,
              let data = pdfData(from: args["data"])
        else {
          result(FlutterError(code: "invalid_args", message: "widthMm/heightMm/data required", details: nil))
          return
        }
        LabelPrintHelper.print(name: name, widthMm: widthMm, heightMm: heightMm, pdfData: data)
        result(true)

      case "saveLabelPdf":
        let fileName = args["fileName"] as? String ?? "label_stok.pdf"
        guard let data = pdfData(from: args["data"]) else {
          result(FlutterError(code: "invalid_args", message: "data required", details: nil))
          return
        }
        let path = LabelPrintHelper.saveToDocuments(fileName: fileName, pdfData: data)
        result(path)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func pdfData(from value: Any?) -> Data? {
    if let typed = value as? FlutterStandardTypedData {
      return typed.data
    }
    if let data = value as? Data {
      return data
    }
    return nil
  }
}

private enum LabelPrintHelper {
  static func saveToDocuments(fileName: String, pdfData: Data) -> String {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = dir.appendingPathComponent(fileName)
    try? pdfData.write(to: url, options: .atomic)
    return url.path
  }

  static func print(name: String, widthMm: Double, heightMm: Double, pdfData: Data) {
    guard let provider = CGDataProvider(data: pdfData as CFData),
          let pdfDocument = CGPDFDocument(provider)
    else {
      return
    }

    let widthPt = widthMm / 25.4 * 72.0
    let heightPt = heightMm / 25.4 * 72.0
    let paperSize = CGSize(width: widthPt, height: heightPt)
    let renderer = LabelPrintRenderer(paperSize: paperSize, pdfDocument: pdfDocument)

    DispatchQueue.main.async {
      let controller = UIPrintInteractionController.shared
      controller.delegate = renderer
      let info = UIPrintInfo.printInfo()
      info.jobName = name
      info.outputType = .general
      info.orientation = widthPt > heightPt ? .landscape : .portrait
      controller.printInfo = info
      controller.printPageRenderer = renderer
      controller.present(animated: true, completionHandler: nil)
    }
  }
}

private final class VanessaLabelPrintPaper: UIPrintPaper {
  private let size: CGSize

  init(size: CGSize) {
    self.size = size
  }

  override var paperSize: CGSize { size }
  override var printableRect: CGRect { CGRect(origin: .zero, size: size) }
}

private final class LabelPrintRenderer: UIPrintPageRenderer, UIPrintInteractionControllerDelegate {
  let paperSize: CGSize
  private let pdfDocument: CGPDFDocument

  init(paperSize: CGSize, pdfDocument: CGPDFDocument) {
    self.paperSize = paperSize
    self.pdfDocument = pdfDocument
    super.init()
  }

  override var paperRect: CGRect {
    CGRect(origin: .zero, size: paperSize)
  }

  override var printableRect: CGRect {
    paperRect
  }

  override var numberOfPages: Int {
    pdfDocument.numberOfPages
  }

  override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
    guard let ctx = UIGraphicsGetCurrentContext(),
          let page = pdfDocument.page(at: pageIndex + 1)
    else {
      return
    }

    let media = page.getBoxRect(.mediaBox)
    guard media.width > 0, media.height > 0 else { return }

    ctx.saveGState()
    ctx.translateBy(x: printableRect.minX, y: printableRect.maxY)
    ctx.scaleBy(
      x: printableRect.width / media.width,
      y: -printableRect.height / media.height
    )
    ctx.drawPDFPage(page)
    ctx.restoreGState()
  }

  func printInteractionController(
    _ printController: UIPrintInteractionController,
    choosePaper paperList: [UIPrintPaper]
  ) -> UIPrintPaper {
    VanessaLabelPrintPaper(size: paperSize)
  }
}
