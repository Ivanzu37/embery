// Embery · llevarte a la sesión. Con lo que manda el hook (app, tty, id de iTerm) se trae al frente
// la ventana donde vive: Claude desktop, Terminal (por tty), iTerm (por sesión) o la app que sea.
import AppKit

enum Focus {
    static let claudeDesktop = "com.anthropic.claudefordesktop"

    static func go(_ s: SessionInfo) {
        let w = s.whereInfo
        let bundle = w["__CFBundleIdentifier"] ?? ""
        let entry = w["CLAUDE_CODE_ENTRYPOINT"] ?? ""

        if bundle == claudeDesktop || entry == "claude-desktop" || desktopId(s.id) != nil {
            // mismo enlace que usa la app en su menú del Dock y en Spotlight, con su id de sesión (local_…)
            if let local = desktopId(s.id),
               let u = URL(string: "claude://code/\(s.state == .perm ? "needs-input" : "continue")?session=\(local)&source=embery") {
                log("app \(local)"); NSWorkspace.shared.open(u)
            } else { log("app (sin id)"); activate(claudeDesktop) }
            return
        }
        log("\(bundle.isEmpty ? "?" : bundle) \(w["tty"] ?? "")")
        if bundle == "com.apple.Terminal" || w["TERM_PROGRAM"] == "Apple_Terminal", let tty = w["tty"], !tty.isEmpty {
            osascript("""
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                  end if
                end repeat
              end repeat
              activate
            end tell
            """)
            return
        }
        if bundle == "com.googlecode.iterm2" || w["TERM_PROGRAM"] == "iTerm.app",
           let sid = w["ITERM_SESSION_ID"]?.split(separator: ":").last {
            osascript("""
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if unique id of s is "\(sid)" then
                      select w
                      tell t to select
                      tell s to select
                    end if
                  end repeat
                end repeat
              end repeat
              activate
            end tell
            """)
            return
        }
        if !bundle.isEmpty { activate(bundle) }
    }

    // La app guarda cada sesión en claude-code-sessions/<cuenta>/<org>/local_….json con el id de Claude Code (cliSessionId).
    private static var desktopIds: [String: String] = [:]
    static func desktopId(_ cli: String) -> String? {
        if let hit = desktopIds[cli] { return hit }
        let root = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"))
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        let needle = Data(cli.utf8)
        for case let url as URL in e where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            guard let d = try? Data(contentsOf: url), d.range(of: needle) != nil,
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  o["cliSessionId"] as? String == cli, let local = o["sessionId"] as? String else { continue }
            desktopIds[cli] = local
            return local
        }
        return nil
    }

    // Una conversación nueva de Claude Code en la carpeta, donde diga Ajustes › Integraciones › Claude Code.
    static func nuevaSesion(en carpeta: URL, terminal: String?) {
        if let g = guion(carpeta.path, terminal: terminal) { osascript(g) } else { activate(claudeDesktop) }
    }

    // shortcut: con «app» solo trae la app de Claude al frente; no hay un enlace documentado para abrirla en una carpeta.
    static func guion(_ carpeta: String, terminal: String?) -> String? {
        let shell = "cd '\(carpeta.replacingOccurrences(of: "'", with: "'\\''"))' && claude"
        let orden = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch terminal ?? "terminal" {
        case "app": return nil
        case "iterm":
            return """
            tell application "iTerm"
              activate
              set w to (create window with default profile)
              tell current session of w to write text "\(orden)"
            end tell
            """
        default:
            return """
            tell application "Terminal"
              activate
              do script "\(orden)"
            end tell
            """
        }
    }

    // Último clic, para depurar sin ver la pantalla (EMBERY_DIR/state.json → "click").
    static var last = ""
    static func log(_ s: String) { last = "\(Date().formatted(date: .omitted, time: .standard)) \(s)" }

    static func activate(_ bundle: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // La primera vez macOS pregunta si Embery puede controlar Terminal/iTerm (Ajustes › Privacidad › Automatización).
    static func osascript(_ script: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
}
