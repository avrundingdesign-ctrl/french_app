import SwiftUI
import SwiftData

// MARK: - Zertifikats-Galerie (Profil)

struct CertificateGalleryView: View {
    @Query private var certificates: [EarnedCertificate]
    @Query private var settingsList: [UserSettings]

    private let content = ContentStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(content.levels) { level in
                    if let certificate = certificate(for: level) {
                        NavigationLink {
                            CertificateDetailView(certificate: certificate, name: certificateName)
                        } label: {
                            CertificateCardView(
                                level: level,
                                name: certificateName,
                                date: certificate.date,
                                score: certificate.score,
                                serial: certificate.serial
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        lockedPlaceholder(level)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Zertifikate")
    }

    private var certificateName: String {
        let name = settingsList.first?.certificateName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Apprenant·e de français" : name
    }

    private func certificate(for level: CEFRLevel) -> EarnedCertificate? {
        certificates.first { $0.levelRaw == level.rawValue }
    }

    private func lockedPlaceholder(_ level: CEFRLevel) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 52, height: 52)
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Zertifikat \(level.rawValue)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Bestehe die Niveau-Prüfung \(level.rawValue), um es freizuschalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .opacity(0.75)
    }
}

// MARK: - Detailansicht mit Teilen

struct CertificateDetailView: View {
    let certificate: EarnedCertificate
    let name: String

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let level = certificate.level {
                    CertificateCardView(
                        level: level,
                        name: name,
                        date: certificate.date,
                        score: certificate.score,
                        serial: certificate.serial
                    )
                    .padding(.horizontal)
                    .padding(.top, 16)

                    ShareLink(
                        item: renderedImage(level: level),
                        preview: SharePreview(
                            "Certificat de français — Niveau \(level.rawValue)",
                            image: renderedImage(level: level)
                        )
                    ) {
                        Label("Als Bild teilen", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.levelColor(level))
                    .padding(.horizontal, 24)

                    Text("Hinweis: Dieses Zertifikat bestätigt deinen Lernfortschritt in der App. Es ist kein offizielles DELF-Diplom.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Zertifikat \(certificate.levelRaw)")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func renderedImage(level: CEFRLevel) -> Image {
        let card = CertificateCardView(
            level: level,
            name: name,
            date: certificate.date,
            score: certificate.score,
            serial: certificate.serial
        )
        .frame(width: 700)
        .padding(24)
        .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let image = renderer.uiImage {
            return Image(uiImage: image)
        }
        return Image(systemName: "doc.richtext")
    }
}

// MARK: - Das Zertifikat selbst

struct CertificateCardView: View {
    let level: CEFRLevel
    let name: String
    let date: Date
    let score: Double
    let serial: String

    var body: some View {
        VStack(spacing: 14) {
            tricolore
                .frame(height: 5)
                .clipShape(Capsule())
                .padding(.horizontal, 40)

            Text("CERTIFICAT DE FRANÇAIS")
                .font(.caption.bold())
                .tracking(3)
                .foregroundStyle(.secondary)

            ZStack {
                Image(systemName: "seal.fill")
                    .font(.system(size: 74))
                    .foregroundStyle(Theme.levelColor(level).gradient)
                Text(level.rawValue)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            VStack(spacing: 3) {
                Text(name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("a réussi l'examen de niveau \(level.rawValue) (CECRL)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(level.rawValue) — \(level.subtitle)")
                    .font(.caption)
                    .foregroundStyle(Theme.levelColor(level))
            }

            HStack(spacing: 20) {
                detail(label: "Ergebnis", value: "\(Int(score.rounded()))/100")
                detail(label: "Datum", value: date.formatted(date: .numeric, time: .omitted))
                detail(label: "Nr.", value: serial)
            }
            .padding(.top, 2)

            tricolore
                .frame(height: 5)
                .clipShape(Capsule())
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.levelColor(level).opacity(0.5), lineWidth: 1.5)
                .padding(5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.levelColor(level).opacity(0.25), lineWidth: 1)
        )
    }

    private var tricolore: some View {
        HStack(spacing: 0) {
            Color(red: 0, green: 85 / 255, blue: 164 / 255)
            Color.white
            Color(red: 239 / 255, green: 65 / 255, blue: 53 / 255)
        }
    }

    private func detail(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
        }
    }
}
