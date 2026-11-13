import SwiftUI

/// ARound's visual identity: a sunny day out. Warm cream canvas, plum ink,
/// and a handful of bright colours that show up in the sound rings.
/// The recurring shape is the ring: AR + around + sound.
enum ARTheme {
  // Canvas and ink
  static let canvas = Color(red: 1.000, green: 0.965, blue: 0.898)      // #FFF6E5 cream
  static let canvasWarm = Color(red: 1.000, green: 0.890, blue: 0.827)  // #FFE3D3 peach
  static let ink = Color(red: 0.169, green: 0.129, blue: 0.251)         // #2B2140 plum
  static let inkSoft = Color(red: 0.169, green: 0.129, blue: 0.251).opacity(0.66)
  static let inkFaint = Color(red: 0.169, green: 0.129, blue: 0.251).opacity(0.42)

  // Brights
  static let coral = Color(red: 0.957, green: 0.325, blue: 0.227)       // #F4533A main colour
  static let sunny = Color(red: 1.000, green: 0.800, blue: 0.220)       // #FFCC38
  static let sky = Color(red: 0.239, green: 0.706, blue: 0.949)         // #3DB4F2
  static let mint = Color(red: 0.180, green: 0.769, blue: 0.651)        // #2EC4A6
  static let grape = Color(red: 0.482, green: 0.361, blue: 1.000)       // #7B5CFF

  // Surfaces
  static let card = Color.white.opacity(0.78)
  static let cardStroke = Color(red: 0.169, green: 0.129, blue: 0.251).opacity(0.07)
  /// Solid bubble for anything floating over the camera view.
  static let bubble = Color.white.opacity(0.95)

  // Type: rounded everywhere, heavier for anything the guide "says".
  static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
  }

  static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .rounded)
  }

  static let cornerRadius: CGFloat = 24
}

/// Cream-to-peach canvas with a few soft blobs of colour drifting behind the content.
struct ARBackground: View {
  var body: some View {
    GeometryReader { geo in
      ZStack {
        LinearGradient(
          colors: [ARTheme.canvas, ARTheme.canvasWarm],
          startPoint: .top,
          endPoint: .bottom
        )
        Circle()
          .fill(ARTheme.sunny.opacity(0.45))
          .frame(width: 260, height: 260)
          .blur(radius: 60)
          .position(x: geo.size.width * 0.88, y: geo.size.height * 0.12)
        Circle()
          .fill(ARTheme.sky.opacity(0.30))
          .frame(width: 240, height: 240)
          .blur(radius: 70)
          .position(x: geo.size.width * 0.08, y: geo.size.height * 0.42)
        Circle()
          .fill(ARTheme.coral.opacity(0.22))
          .frame(width: 300, height: 300)
          .blur(radius: 80)
          .position(x: geo.size.width * 0.75, y: geo.size.height * 0.92)
      }
    }
    .ignoresSafeArea()
  }
}

/// The name, drawn so the readings show: AR · around · sound.
struct ARoundWordmark: View {
  var size: CGFloat = 40

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text("AR")
        .font(ARTheme.display(size, weight: .black))
        .foregroundColor(ARTheme.coral)
      Text("ound")
        .font(ARTheme.display(size, weight: .heavy))
        .foregroundColor(ARTheme.ink)
      Image(systemName: "wave.3.right")
        .font(.system(size: size * 0.55, weight: .heavy))
        .foregroundColor(ARTheme.sky)
        .padding(.leading, size * 0.12)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("ARound")
  }
}

/// Colourful rings spreading from a bouncy centre disc, like sound travelling outward.
/// Still when idle, pulsing when the guide is live.
struct SoundRings: View {
  var isActive: Bool = true
  var color: Color = ARTheme.coral
  var symbol: String = "waveform"

  var body: some View {
    // Rebuild when the state flips so the pulse animation restarts cleanly.
    SoundRingsContent(isActive: isActive, color: color, symbol: symbol)
      .id(isActive)
  }
}

private struct SoundRingsContent: View {
  let isActive: Bool
  let color: Color
  let symbol: String

  @State private var pulse = false
  @State private var bounce = false

  private let ringColors: [Color] = [ARTheme.coral, ARTheme.sunny, ARTheme.sky]

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ZStack {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .stroke(ringColors[index].opacity(isActive ? 0.9 : 0.55), lineWidth: 5)
            .scaleEffect(ringScale(index))
            .opacity(isActive ? (pulse ? 0.0 : 1.0) : 1.0)
            .animation(
              isActive
                ? Animation.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(index) * 0.8)
                : Animation.default,
              value: pulse
            )
        }

        Circle()
          .fill(
            LinearGradient(
              colors: [color, ARTheme.sunny],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: side * 0.4, height: side * 0.4)
          .shadow(color: color.opacity(0.35), radius: 14, y: 8)
          .scaleEffect(bounce ? 1.07 : 0.96)

        Image(systemName: symbol)
          .font(.system(size: side * 0.16, weight: .heavy))
          .foregroundColor(.white)
          .scaleEffect(bounce ? 1.07 : 0.96)

        // The dot: you, on the ring around you.
        Circle()
          .fill(ARTheme.grape)
          .frame(width: side * 0.08, height: side * 0.08)
          .overlay(Circle().stroke(Color.white, lineWidth: 2))
          .offset(x: side * 0.25, y: -side * 0.25)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .aspectRatio(1, contentMode: .fit)
    .onAppear {
      pulse = true
      if isActive {
        withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          bounce = true
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func ringScale(_ index: Int) -> CGFloat {
    if isActive {
      return pulse ? 1.0 : 0.42
    }
    return 0.55 + CGFloat(index) * 0.2
  }
}

/// Soft white card used for grouped information on the cream canvas.
struct ARCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(ARTheme.card)
      .clipShape(RoundedRectangle(cornerRadius: ARTheme.cornerRadius))
      .overlay(
        RoundedRectangle(cornerRadius: ARTheme.cornerRadius)
          .stroke(ARTheme.cardStroke, lineWidth: 1)
      )
      .shadow(color: ARTheme.ink.opacity(0.06), radius: 12, y: 6)
  }
}

extension View {
  func arCard() -> some View {
    modifier(ARCardModifier())
  }

  /// Soft drop shadow that lifts bubbles and buttons off the camera view.
  func arFloat() -> some View {
    shadow(color: ARTheme.ink.opacity(0.16), radius: 10, y: 5)
  }
}
