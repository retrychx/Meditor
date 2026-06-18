import Foundation

/// Static content store for all built-in templates and HTML theme CSS.
/// No logic lives here — only string constants.
enum BuiltinTemplates {

    // MARK: - Markdown templates

    static var meeting: String { """
    # Meeting Notes

    **Date:** \(datePlaceholder)
    **Attendees:**

    - [ ] Name 1
    - [ ] Name 2

    ## Agenda

    1.

    ## Discussion

    ## Action Items

    | Owner | Task | Due |
    |-------|------|-----|
    |       |      |     |
    """ }

    static var techDesign: String { """
    # Technical Design

    ## Background

    ## Goals

    - [ ]

    ## Non-Goals

    -

    ## Design

    ### Architecture

    ### API

    ### Data Model

    ## Implementation Plan

    | Phase | Task | Estimate |
    |-------|------|----------|
    | 1     |      |          |

    ## Risks

    ## Open Questions
    """ }

    static var weekly: String { """
    # Weekly Report

    **Week of:** \(datePlaceholder)

    ## Done This Week

    -

    ## In Progress

    -

    ## Blockers

    -

    ## Plan for Next Week

    -

    ## Notes
    """ }

    static var journal: String { """
    # \(datePlaceholder)

    ## Today's Focus

    -

    ## Notes

    ## Learnings

    ## Tomorrow
    """ }

    // MARK: - Theme token defaults

    struct ThemeTokenDefaults {
        let accent: String
        let bg: String
        let text: String
        let font: String
        let width: String
        let fontMono: String
    }

    static let tufteTokenDefaults = ThemeTokenDefaults(
        accent: "#0066cc",
        bg: "#ffffff",
        text: "#1a1a1a",
        font: "Georgia, 'Times New Roman', serif",
        width: "680px",
        fontMono: "Consolas, 'Courier New', monospace"
    )

    static let craftTokenDefaults = ThemeTokenDefaults(
        accent: "#0066cc",
        bg: "#f5f5f7",
        text: "#1d1d1f",
        font: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
        width: "720px",
        fontMono: "'SF Mono', Menlo, monospace"
    )

    static let darkTokenDefaults = ThemeTokenDefaults(
        accent: "#58a6ff",
        bg: "#0d1117",
        text: "#e6edf3",
        font: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
        width: "760px",
        fontMono: "'SF Mono', Menlo, 'Courier New', monospace"
    )

    // MARK: - Theme helpers

    static func tokenDefaults(for templateID: String) -> ThemeTokenDefaults {
        switch templateID {
        case "html-tufte": return tufteTokenDefaults
        case "html-craft": return craftTokenDefaults
        case "html-dark":  return darkTokenDefaults
        default:           return craftTokenDefaults
        }
    }

    static func css(for templateID: String) -> String {
        switch templateID {
        case "html-tufte": return tufteCSS
        case "html-craft": return craftCSS
        case "html-dark":  return darkCSS
        default:           return craftCSS
        }
    }

    // MARK: - HTML theme CSS (CSS variable–driven)

    static let tufteCSS = """
    :root {
      --accent: #0066cc;
      --bg: #ffffff;
      --text: #1a1a1a;
      --font: Georgia, 'Times New Roman', serif;
      --width: 680px;
      --font-mono: Consolas, 'Courier New', monospace;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        font-family: var(--font);
        font-size: 16px; line-height: 1.6; color: var(--text);
        background: var(--bg); max-width: var(--width); margin: 0 auto; padding: 48px 24px;
    }
    h1, h2, h3 { font-family: var(--font); font-variant: small-caps; font-weight: normal; letter-spacing: 0.04em; color: var(--text); }
    h1 { font-size: 1.8em; border-bottom: 1px solid #ccc; padding-bottom: 8px; margin: 32px 0 16px; }
    h2 { font-size: 1.3em; border-bottom: 1px solid #e0e0e0; padding-bottom: 4px; margin: 28px 0 12px; }
    h3 { font-size: 1.1em; margin: 20px 0 10px; }
    p  { margin: 0 0 14px; }
    a  { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote { border-left: 3px solid #666; background: #f9f9f9; margin: 16px 0; padding: 10px 16px; color: #444; font-style: italic; }
    pre { background: #f4f4f4; border: 1px solid #ddd; border-radius: 4px; padding: 14px 16px; overflow-x: auto; margin: 16px 0; }
    code { font-family: var(--font-mono); font-size: 0.88em; background: #f4f4f4; padding: 1px 4px; border-radius: 3px; }
    pre code { background: none; padding: 0; }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 0.92em; }
    th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
    th { background: #f4f4f4; font-weight: bold; }
    hr { border: none; border-top: 1px solid #ccc; margin: 28px 0; }
    ul, ol { padding-left: 24px; margin: 0 0 14px; }
    li { margin-bottom: 4px; }
    """

    static let craftCSS = """
    :root {
      --accent: #0066cc;
      --bg: #f5f5f7;
      --text: #1d1d1f;
      --font: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      --width: 720px;
      --font-mono: 'SF Mono', Menlo, monospace;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        font-family: var(--font);
        font-size: 15px; line-height: 1.65; color: var(--text);
        background: var(--bg); max-width: var(--width); margin: 0 auto; padding: 32px 20px;
    }
    article, section { background: #fff; border-radius: 12px; padding: 28px 32px; margin-bottom: 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.07), 0 4px 16px rgba(0,0,0,0.04); }
    h1 { font-size: 1.75em; font-weight: 700; letter-spacing: -0.02em; color: var(--text); margin: 0 0 18px; }
    h2 { font-size: 1.25em; font-weight: 600; color: var(--text); margin: 24px 0 10px; }
    h3 { font-size: 1.05em; font-weight: 600; color: #444; margin: 18px 0 8px; }
    p  { margin: 0 0 12px; color: #333; }
    a  { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote { border-left: 3px solid var(--accent); background: #f0f4ff; margin: 14px 0; padding: 10px 16px; border-radius: 0 8px 8px 0; color: #444; }
    pre { background: #f0f0f5; border-radius: 8px; padding: 16px; overflow-x: auto; margin: 14px 0; }
    code { font-family: var(--font-mono); font-size: 0.86em; background: #f0f0f5; color: #6e40c9; padding: 1px 5px; border-radius: 4px; }
    pre code { background: none; padding: 0; color: var(--text); }
    table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 0.91em; }
    th, td { border: 1px solid #e5e5ea; padding: 8px 14px; text-align: left; }
    th { background: #f5f5f7; font-weight: 600; }
    hr { border: none; border-top: 1px solid #e5e5ea; margin: 24px 0; }
    ul, ol { padding-left: 22px; margin: 0 0 12px; }
    li { margin-bottom: 5px; }
    """

    static let darkCSS = """
    :root {
      --accent: #58a6ff;
      --bg: #0d1117;
      --text: #e6edf3;
      --font: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      --width: 760px;
      --font-mono: 'SF Mono', Menlo, 'Courier New', monospace;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        font-family: var(--font);
        font-size: 15px; line-height: 1.7; color: var(--text);
        background: var(--bg); max-width: var(--width); margin: 0 auto; padding: 48px 24px;
    }
    h1 { font-size: 2em; font-weight: 700; background: linear-gradient(90deg, #79c0ff, #a5a6ff); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; margin: 0 0 20px; }
    h2 { font-size: 1.4em; font-weight: 600; background: linear-gradient(90deg, #58a6ff, #bc8cff); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; margin: 32px 0 12px; padding-bottom: 8px; border-bottom: 1px solid #21262d; }
    h3 { font-size: 1.15em; font-weight: 600; color: #c9d1d9; margin: 24px 0 8px; }
    p  { margin: 0 0 14px; color: #c9d1d9; }
    a  { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote { border-left: 3px solid #39d353; background: #161b22; margin: 16px 0; padding: 12px 16px; border-radius: 0 6px 6px 0; color: #8b949e; font-style: italic; }
    pre { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 16px; overflow-x: auto; margin: 16px 0; }
    code { font-family: var(--font-mono); font-size: 0.86em; background: #161b22; color: #39d353; padding: 2px 5px; border-radius: 4px; }
    pre code { background: none; padding: 0; color: var(--text); }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 0.91em; }
    th, td { border: 1px solid #30363d; padding: 8px 14px; text-align: left; }
    th { background: #161b22; font-weight: 600; color: #c9d1d9; }
    hr { border: none; border-top: 1px solid #21262d; margin: 28px 0; }
    ul, ol { padding-left: 22px; margin: 0 0 14px; }
    li { margin-bottom: 5px; color: #c9d1d9; }
    """

    // MARK: - Full HTML theme templates

    static var htmlTufte: String { htmlShell(title: "Tufte Document", css: tufteCSS) }
    static var htmlCraft: String { htmlShell(title: "Craft Document", css: craftCSS) }
    static var htmlDark:  String { htmlShell(title: "Dark Document",  css: darkCSS)  }

    // MARK: - Private helpers

    private static var datePlaceholder: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private static func htmlShell(title: String, css: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
            <style>
        \(css)
            </style>
        </head>
        <body>
        <article>
        <h1>\(title)</h1>
        <p>在这里编写正文内容。</p>
        </article>
        </body>
        </html>
        """
    }
}
