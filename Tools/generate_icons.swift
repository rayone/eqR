import AppKit
import WebKit

// Usage: swift Tools/generate_icons.swift
// Renders design/logo.svg and design/menubar*.svg using native WebKit / Cocoa,
// generating AppIcon.icns and MenuBarIconTemplate PNGs without external dependencies (ImageMagick).

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func renderSVGWebKit(svgURL: URL, targetWidth: CGFloat, targetHeight: CGFloat, completion: @escaping (NSImage?) -> Void) {
    guard let svgData = try? Data(contentsOf: svgURL) else {
        print("Error: Could not read SVG at \(svgURL.path)")
        completion(nil)
        return
    }

    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    webView.setValue(false, forKey: "drawsBackground")
    webView.load(svgData, mimeType: "image/svg+xml", characterEncodingName: "UTF-8", baseURL: svgURL.deletingLastPathComponent())

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("Snapshot error for \(svgURL.lastPathComponent): \(error)")
                completion(nil)
            } else {
                completion(image)
            }
        }
    }
}

func generateAppIcon(logoURL: URL, destIcnsURL: URL, completion: @escaping (Bool) -> Void) {
    renderSVGWebKit(svgURL: logoURL, targetWidth: 1024, targetHeight: 1024) { fullImage in
        guard let fullImage = fullImage else {
            completion(false)
            return
        }

        let tempIconset = repoRoot.appendingPathComponent("build/AppIcon.iconset")
        try? fileManager.removeItem(at: tempIconset)
        try! fileManager.createDirectory(at: tempIconset, withIntermediateDirectories: true)

        let sizes: [Int] = [16, 32, 128, 256, 512]
        for s in sizes {
            for scale in [1, 2] {
                let pixelSize = s * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: pixelSize,
                                           pixelsHigh: pixelSize,
                                           bitsPerSample: 8,
                                           samplesPerPixel: 4,
                                           hasAlpha: true,
                                           isPlanar: false,
                                           colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0,
                                           bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSGraphicsContext.current?.imageInterpolation = .high
                fullImage.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                              from: NSRect(x: 0, y: 0, width: fullImage.size.width, height: fullImage.size.height),
                              operation: .copy,
                              fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()

                let fileName = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
                let fileURL = tempIconset.appendingPathComponent(fileName)
                let pngData = rep.representation(using: .png, properties: [:])!
                try! pngData.write(to: fileURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", tempIconset.path, "-o", destIcnsURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            completion(process.terminationStatus == 0)
        } catch {
            print("Failed to run iconutil: \(error)")
            completion(false)
        }
    }
}

func generateMenuBarTemplate(svgURL: URL, dest1xURL: URL, dest2xURL: URL) -> Bool {
    guard let img = NSImage(contentsOf: svgURL) else {
        print("Failed to load \(svgURL.lastPathComponent) via NSImage")
        return false
    }

    // 18pt tall for a standard menu bar item, 36pt @2x. Width follows the SVG's
    // own aspect ratio rather than a hardcoded one, so a source of any shape
    // renders at its true proportions instead of being squashed to fit.
    let aspect = img.size.width > 0 && img.size.height > 0 ? img.size.width / img.size.height : 1
    let height1x: CGFloat = 18.0
    let width1x: CGFloat = round(height1x * aspect)
    let height2x: CGFloat = height1x * 2.0
    let width2x: CGFloat = width1x * 2.0

    func savePNG(pixelWidth: Int, pixelHeight: Int, to url: URL) -> Bool {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return false
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
                 from: .zero,
                 operation: .copy,
                 fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try pngData.write(to: url)
            return true
        } catch {
            print("Failed to write \(url.path): \(error)")
            return false
        }
    }

    return savePNG(pixelWidth: Int(width2x), pixelHeight: Int(height2x), to: dest2xURL) &&
           savePNG(pixelWidth: Int(width1x), pixelHeight: Int(height1x), to: dest1xURL)
}

let appName = fileManager.fileExists(atPath: "eqR") ? "eqR" : "eqR"

let logoURL = repoRoot.appendingPathComponent("design/logo.svg")
let destIcnsURL = repoRoot.appendingPathComponent("\(appName)/Resources/AppIcon.icns")
let menubarURL = repoRoot.appendingPathComponent("design/menubar.svg")
let mbDest1x = repoRoot.appendingPathComponent("\(appName)/Resources/MenuBarIconTemplate.png")
let mbDest2x = repoRoot.appendingPathComponent("\(appName)/Resources/MenuBarIconTemplate@2x.png")
let menubarSlashURL = repoRoot.appendingPathComponent("design/menubar-slash.svg")
let mbsDest1x = repoRoot.appendingPathComponent("\(appName)/Resources/MenuBarIconSlashTemplate.png")
let mbsDest2x = repoRoot.appendingPathComponent("\(appName)/Resources/MenuBarIconSlashTemplate@2x.png")

guard generateMenuBarTemplate(svgURL: menubarURL, dest1xURL: mbDest1x, dest2xURL: mbDest2x) else {
    print("Error generating MenuBarIconTemplate")
    exit(1)
}

guard generateMenuBarTemplate(svgURL: menubarSlashURL, dest1xURL: mbsDest1x, dest2xURL: mbsDest2x) else {
    print("Error generating MenuBarIconSlashTemplate")
    exit(1)
}

generateAppIcon(logoURL: logoURL, destIcnsURL: destIcnsURL) { ok in
    if !ok {
        print("Error generating AppIcon.icns")
        exit(1)
    }
    print("Regenerated \(appName)/Resources/AppIcon.icns and \(appName)/Resources/MenuBarIconTemplate*.png")
    exit(0)
}

RunLoop.main.run()
