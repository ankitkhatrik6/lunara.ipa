import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SharePlaylistSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let name: String
    let songIds: [String]
    var kindLabel: String = "PLAYLIST"
    var artworkURL: URL? = nil
    var customLink: String? = nil

    @State private var copied = false

    private var link: String {
        if let customLink, !customLink.isEmpty { return customLink }
        return PlaylistLink.build(name: name, songIds: songIds)
    }

    private var trimmed: Int { max(songIds.count - PlaylistLink.maxSongs, 0) }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            Text("Share")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            shareCardPreview
                .padding(.vertical, 4)

            if trimmed > 0 && customLink == nil {
                Text("The first \(PlaylistLink.maxSongs) songs are included; \(trimmed) did not fit.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            Button {
                sharePicture()
            } label: {
                Text("Share picture")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Lunara.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: {
                    Text(copied ? "Copied" : "Copy link")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                ShareLink(item: link) {
                    Text("Share")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x0B0B0B).ignoresSafeArea())
        .presentationBackground(Color(hex: 0x0B0B0B))
        .presentationDetents([.large])
    }

    private var shareCardPreview: some View {
        ZStack {
            if let artworkURL {
                RemoteImage(url: artworkURL, size: 320) { Color(hex: 0x1A1A1A) }
                    .frame(width: 224, height: 310)
                    .blur(radius: 26)
                    .overlay(Color.black.opacity(0.55))
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x1A2E1F), Color(hex: 0x0D0D0D)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            VStack(spacing: 14) {
                Spacer(minLength: 8)

                if let artworkURL {
                    RemoteImage(url: artworkURL, size: 280) { ArtPlaceholder() }
                        .frame(width: 144, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                } else if let qr = qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 136, height: 136)
                        .padding(10)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(spacing: 4) {
                    Text(kindLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 4)

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x161616))
                            .frame(width: 26, height: 26)
                        Circle()
                            .stroke(Lunara.green.opacity(0.7), lineWidth: 1.4)
                            .frame(width: 18, height: 18)
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Lunara.green)
                    }
                    Text("Lunara")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Listen on Lunara")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.bottom, 16)
            }
            .frame(width: 224, height: 310)
        }
        .frame(width: 224, height: 310)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    @MainActor
    private func sharePicture() {
        let renderer = ImageRenderer(content: shareCardPreview)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return }
        let activity = UIActivityViewController(activityItems: [image, link], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(activity, animated: true)
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
