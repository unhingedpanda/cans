import AppKit
import Combine

/// What's playing on this Mac, from the system Now Playing (the Control Center source), so it
/// works for any app: Spotify, Music, browsers, podcasts. macOS doesn't pass track metadata to
/// the headphones, and since 15.4 MediaRemote only answers Apple-signed processes, so a tiny
/// helper library (NowPlayingHelper) runs inside /usr/bin/perl and streams changes as JSON lines.
/// The stream runs only while the popover is open.
@MainActor
final class NowPlaying: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String?
        var isPlaying: Bool
        var appName: String?
    }

    @Published private(set) var track: Track?
    private var stream: Process?
    private var buffer = Data()

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let loader = """
    require DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($h, $ARGV[1]) or die "missing $ARGV[1]";
    DynaLoader::dl_install_xsub("main::run", $s);
    run();
    """
    private static var helper: String? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("libCansNowPlaying.dylib").path
    }

    func start() {
        guard stream == nil, let helper = Self.helper else { return }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.loader, helper, "cans_stream"]
        let output = Pipe()
        process.standardOutput = output
        process.standardInput = Pipe()  // closing it on stop() ends the helper
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        do {
            try process.run()
            stream = process
        } catch {
            track = nil
        }
    }

    func stop() {
        guard let process = stream else { return }
        (process.standardInput as? Pipe)?.fileHandleForWriting.closeFile()
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminate()
        stream = nil
        buffer.removeAll()
    }

    /// Play/pause, next or previous in whichever app owns Now Playing.
    func perform(_ command: String) {
        guard let helper = Self.helper else { return }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.loader, helper, "cans_command"]
        process.environment = ["CANS_COMMAND": command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            guard let title = json["title"] as? String, !title.isEmpty else {
                track = nil
                continue
            }
            let bundleID = json["app"] as? String
            let appName = bundleID
                .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            let next = Track(title: title, artist: (json["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             isPlaying: (json["playing"] as? Bool) ?? ((json["playing"] as? Int) == 1),
                             appName: appName)
            if next != track { track = next }
        }
    }
}
