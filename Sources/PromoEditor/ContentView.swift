import AVKit
import SwiftUI
import PromoEditorCore
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var editor: EditorModel
    @State private var player = AVPlayer()
    @State private var clipToTrim: TimelineClip?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                mediaLibrary
                    .frame(width: 300)
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                timeline
                    .frame(width: 340)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: editor.previewURL) { _, url in
            guard let url else {
                player.replaceCurrentItem(with: nil)
                return
            }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.seek(to: .zero)
        }
        .sheet(item: $clipToTrim) { clip in
            TrimClipView(clip: clip) { start, end in
                editor.updateTrim(for: clip, start: start, end: end)
                clipToTrim = nil
            } onCancel: {
                clipToTrim = nil
            }
        }
        .alert("Promo Editor", isPresented: Binding(
            get: { editor.alertMessage != nil },
            set: { if !$0 { editor.alertMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) { editor.alertMessage = nil }
        } message: {
            Text(editor.alertMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Promo Editor")
                    .font(.headline)
                Text("Promocionales verticales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editor.openProject()
            } label: {
                Label("Abrir proyecto", systemImage: "folder")
            }
            .help("Abre un proyecto .json de Promo Editor")

            Button {
                editor.saveProject()
            } label: {
                Label("Guardar proyecto", systemImage: "square.and.arrow.down")
            }
            .disabled(editor.timeline.isEmpty)

            Button {
                editor.exportPromo()
            } label: {
                Label(editor.isExporting ? "Exportando…" : "Exportar MP4", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(editor.timeline.isEmpty || editor.isExporting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var mediaLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VIDEOS")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editor.chooseFolder()
                } label: {
                    Label("Abrir carpeta", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Abre una carpeta con videos")
            }

            if let folder = editor.sourceFolderURL {
                Text(folder.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(folder.path)
            } else {
                Text("Elige la carpeta donde están tus clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if editor.isLoading {
                ProgressView("Analizando videos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if editor.library.isEmpty {
                ContentUnavailableView(
                    "Sin clips",
                    systemImage: "video",
                    description: Text("Abre una carpeta para ver tus videos.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(editor.library) { clip in
                            MediaRow(
                                clip: clip,
                                isSelected: editor.selectedLibraryPath == clip.url.path,
                                onSelect: { editor.selectForPreview(clip) },
                                onAdd: { editor.addToTimeline(clip) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
    }

    private var preview: some View {
        VStack(spacing: 14) {
            HStack {
                Text("VISTA PREVIA")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                if let url = editor.previewURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            if editor.previewURL != nil {
                NativeVideoPlayer(player: player)
                    .frame(width: 330, height: 586)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            } else {
                ContentUnavailableView(
                    "Vista previa",
                    systemImage: "play.rectangle",
                    description: Text("Selecciona un clip de la biblioteca o de la secuencia.")
                )
                .frame(width: 330, height: 586)
            }
            Spacer(minLength: 0)

            if let selectedPath = editor.selectedLibraryPath,
               let clip = editor.library.first(where: { $0.url.path == selectedPath }) {
                Button {
                    editor.addToTimeline(clip)
                } label: {
                    Label("Añadir a la secuencia", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SECUENCIA")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text("\(editor.timeline.count) tomas · \(formatTime(editor.totalDuration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("MÚSICA DE FONDO", systemImage: "music.note")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editor.chooseMusic()
                    } label: {
                        Label(editor.backgroundMusicURL == nil ? "Añadir" : "Cambiar", systemImage: "plus")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                if let musicURL = editor.backgroundMusicURL {
                    HStack(spacing: 5) {
                        Text(musicURL.lastPathComponent)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            editor.removeMusic()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Quitar música")
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $editor.musicVolume, in: 0...0.6)
                        Text("\(Int(editor.musicVolume * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Audio original silenciado.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(9)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            vfxPanel

            if editor.timeline.isEmpty {
                ContentUnavailableView(
                    "Tu promocional",
                    systemImage: "rectangle.stack",
                    description: Text("Añade clips y ordénalos aquí.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(editor.timeline.enumerated()), id: \.element.id) { index, clip in
                            TimelineRow(
                                number: index + 1,
                                clip: clip,
                                isSelected: editor.selectedTimelineID == clip.id,
                                onSelect: { editor.selectForPreview(clip) },
                                onTrim: { clipToTrim = clip },
                                onMoveUp: { editor.move(clip, by: -1) },
                                onMoveDown: { editor.move(clip, by: 1) },
                                onRemove: { editor.removeFromTimeline(clip) }
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private var vfxPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("EFECTOS VISUALES", systemImage: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            TextField("Título de apertura", text: $editor.vfxSettings.openingText)
                .textFieldStyle(.roundedBorder)
            TextField("Texto final / llamada a la acción", text: $editor.vfxSettings.closingText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                if let logoPath = editor.vfxSettings.logoPath {
                    Text(URL(fileURLWithPath: logoPath).lastPathComponent)
                        .font(.system(size: 10))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        editor.removeLogo()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Quitar logo")
                } else {
                    Button {
                        editor.chooseLogo()
                    } label: {
                        Label("Añadir logo", systemImage: "photo")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            Text("Títulos animados y logo en zona segura para vertical.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(9)
        .background(Color.accentColor.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if editor.isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            }
            Text(editor.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Salida 9:16 · 1080 × 1920")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
    }
}

private struct MediaRow: View {
    let clip: MediaClip
    let isSelected: Bool
    let onSelect: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onSelect) {
                HStack(spacing: 9) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clip.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(formatTime(clip.duration)) · \(clip.width)×\(clip.height)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previsualizar \(clip.name)")

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .help("Añadir a la secuencia")
        }
        .padding(7)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thumbnail: some View {
        Group {
            if let data = clip.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 42, height: 58)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct TimelineRow: View {
    let number: Int
    let clip: TimelineClip
    let isSelected: Bool
    let onSelect: () -> Void
    let onTrim: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d", number))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(formatTime(clip.selectedDuration)) seleccionados")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button(action: onTrim) {
                    Label("Recortar", systemImage: "scissors")
                }
                .help("Ajustar inicio y fin de esta toma")
                Spacer(minLength: 0)
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .help("Mover arriba")
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .help("Mover abajo")
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .help("Quitar de la secuencia")
            }
            .font(.system(size: 11))
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrimClipView: View {
    let clip: TimelineClip
    let onSave: (Double, Double) -> Void
    let onCancel: () -> Void
    @State private var start: Double
    @State private var end: Double

    init(clip: TimelineClip, onSave: @escaping (Double, Double) -> Void, onCancel: @escaping () -> Void) {
        self.clip = clip
        self.onSave = onSave
        self.onCancel = onCancel
        _start = State(initialValue: clip.trimStart)
        _end = State(initialValue: clip.trimEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recortar toma")
                .font(.title2.weight(.semibold))
            Text(clip.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inicio")
                    Spacer()
                    Text(formatTime(start))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $start, in: 0...max(0, end - 0.1))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fin")
                    Spacer()
                    Text(formatTime(end))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $end, in: min(clip.duration, start + 0.1)...clip.duration)
            }

            HStack {
                Text("Duración seleccionada: \(formatTime(max(0, end - start)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Aplicar") { onSave(start, end) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let wholeSeconds = max(0, Int(seconds.rounded()))
    let minutes = wholeSeconds / 60
    let remainder = wholeSeconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}
