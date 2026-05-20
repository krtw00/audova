// Audova アイコン生成 (AUD-12)。
// 流れる波形リボン × ダーク squircle 背景を Core Graphics で描く。
// 詳細版 (large, 128px 以上) と 小サイズ簡略版 (small, 16/32/64) の 2 枚を /tmp に出力する。
// iconset 化 + icns 生成は scripts/build_icns.sh が担当する。
//
// 実行: swift scripts/generate_icon.swift

import AppKit
import CoreGraphics

let SIZE: CGFloat = 1024

func makeContext() -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    return CGContext(data: nil, width: Int(SIZE), height: Int(SIZE),
                     bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ ctx: CGContext, _ path: String) {
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// 両端で振幅が 0 に収束する (envelope) 流れる波形パス。
func ribbonPath(cycles: Double, ampRatio: CGFloat, midRatio: CGFloat) -> CGMutablePath {
    let p = CGMutablePath()
    let midY = SIZE * midRatio
    let baseAmp = SIZE * ampRatio
    let steps = 300
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let x = CGFloat(t) * SIZE
        let env = sin(Double.pi * t)
        let y = midY + CGFloat(env) * baseAmp * CGFloat(sin(2 * Double.pi * cycles * t))
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    return p
}

/// metalColors: リボンの上端→下端の金属縦グラデ。 vignette: 四隅をわずかに落とす。
func drawIcon(cycles: Double, ampRatio: CGFloat, ribbonW: CGFloat,
              metalColors: [CGColor], vignette: Bool, to path: String) {
    let ctx = makeContext()
    let cs = CGColorSpaceCreateDeviceRGB()
    let full = CGRect(x: 0, y: 0, width: SIZE, height: SIZE)

    ctx.saveGState()
    ctx.addPath(squircle(full, SIZE * 0.225)); ctx.clip()

    // 背景: やや青み黒の縦グラデ
    let bg = CGGradient(colorsSpace: cs,
                        colors: [rgb(0.15, 0.16, 0.19), rgb(0.055, 0.06, 0.075)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: SIZE), end: CGPoint(x: 0, y: 0), options: [])

    // リボン本体: 太線 stroke → clip → 縦金属グラデ
    let yHi = SIZE * 0.5 + SIZE * ampRatio + ribbonW / 2
    let yLo = SIZE * 0.5 - SIZE * ampRatio - ribbonW / 2
    ctx.saveGState()
    ctx.addPath(ribbonPath(cycles: cycles, ampRatio: ampRatio, midRatio: 0.5))
    ctx.setLineWidth(ribbonW)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let n = metalColors.count
    let locs: [CGFloat] = (0..<n).map { CGFloat($0) / CGFloat(n - 1) }
    let metal = CGGradient(colorsSpace: cs, colors: metalColors as CFArray, locations: locs)!
    ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: yHi), end: CGPoint(x: 0, y: yLo),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    if vignette {
        let vig = CGGradient(colorsSpace: cs, colors: [rgb(0,0,0,0), rgb(0,0,0,0.30)] as CFArray, locations: [0,1])!
        ctx.drawRadialGradient(vig, startCenter: CGPoint(x: SIZE/2, y: SIZE/2), startRadius: SIZE*0.32,
                               endCenter: CGPoint(x: SIZE/2, y: SIZE/2), endRadius: SIZE*0.72, options: [])
    }
    ctx.restoreGState()
    savePNG(ctx, path)
}

// 詳細版 (128px 以上): 細め・振幅大・金属コントラスト強・ビネットあり
drawIcon(cycles: 1.5, ampRatio: 0.17, ribbonW: SIZE * 0.075,
         metalColors: [rgb(0.98,0.99,1.00), rgb(0.78,0.82,0.88), rgb(0.52,0.57,0.65), rgb(0.36,0.40,0.48)],
         vignette: true, to: "/tmp/audova_icon_large.png")

// 簡略版 (16/32/64): 太め・振幅控えめ・明るめ金属 (暗部で潰れない)・ビネットなし
drawIcon(cycles: 1.5, ampRatio: 0.11, ribbonW: SIZE * 0.135,
         metalColors: [rgb(0.99,0.99,1.00), rgb(0.84,0.87,0.92), rgb(0.66,0.70,0.77)],
         vignette: false, to: "/tmp/audova_icon_small.png")
