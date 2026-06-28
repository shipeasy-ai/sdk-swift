import SwiftUI

/// The whole guide: a single scrollable "big guide document" — a hero header,
/// the placeholder banner, one card per Shipeasy entity, then a footer.
struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Hero()
                PlaceholderBanner()

                ForEach(Entity.all) { entity in
                    EntityCard(entity: entity)
                }

                Footer()
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Hero

private struct Hero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shipeasy · Swift Entity Guide")
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("One card per Shipeasy entity — what it is, a live sample value, and the exact SDK call to make it real.")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Placeholder banner

private struct PlaceholderBanner: View {
    var body: some View {
        Text("⚠ SDK not wired yet — every value below is a placeholder. Add the Shipeasy Swift package and replace the TODOs to make them live.")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#fbbf24").opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(hex: "#fbbf24").opacity(0.45), lineWidth: 1)
            )
    }
}

// MARK: - Entity card

private struct EntityCard: View {
    let entity: Entity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: [type-label chip] + Spacer + [value chip]
            HStack(alignment: .top, spacing: 8) {
                Chip(text: entity.label, accent: entity.accent)
                Spacer(minLength: 8)
                Chip(text: entity.value, accent: entity.accent)
                    .layoutPriority(1)
            }

            // Key (monospace title)
            Text(entity.key)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            // Description
            Text(entity.description)
                .font(.system(.callout))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Code block
            CodeBlock(code: entity.call)

            // Faint meta line
            Text(entity.meta)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Pieces

/// An accent-tinted chip: bg = accent @ ~14% opacity, accent-coloured text.
private struct Chip: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .foregroundStyle(accent)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous).fill(accent.opacity(0.14))
            )
    }
}

/// A monospace code block on the nested `#0f0f10` surface.
private struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.codeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Footer

private struct Footer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run note: this app makes zero network calls — every value is a hardcoded placeholder. Install the Shipeasy Swift package and replace each // TODO to go live.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Link("docs.shipeasy.ai", destination: URL(string: "https://docs.shipeasy.ai")!)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(hex: "#60a5fa"))
        }
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
}
