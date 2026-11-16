import AppKit

// Finder window artwork; application icons and labels are placed by dmgbuild.
let size = NSSize(width: 700, height: 500)
let title = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Drive"
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(calibratedRed: 0.06, green: 0.15, blue: 0.23, alpha: 1).setFill()
NSRect(x: 0, y: 380, width: 700, height: 120).fill()
func text(_ value: String, _ x: CGFloat, _ top: CGFloat, _ fontSize: CGFloat, _ color: NSColor, bold: Bool = false) {
    let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
    let string = value as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let bounds = string.size(withAttributes: attributes)
    string.draw(at: NSPoint(x: x, y: size.height - top - bounds.height), withAttributes: attributes)
}
text(title.uppercased(), 38, 24, 34, .white, bold: true)
text("Перетащите \(title) в папку «Программы»", 40, 75, 19, .white)
let ink = NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.29, alpha: 1)
text("→", 317, 190, 57, ink)
text("После копирования откройте \(title) из «Программ».", 75, 310, 17, ink)
text("Если macOS блокирует запуск, прочитайте «Установка.txt».", 107, 340, 13, ink)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
