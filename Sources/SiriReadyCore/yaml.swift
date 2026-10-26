import Foundation

/// A minimal reader for the YAML subset used by `siriready.yaml` (Foundation only, no dependencies).
///
/// Supported: nested block mappings, block sequences of scalars, inline `[a, b]` sequences,
/// single/double-quoted scalars and `#` comments. Anchors, multi-line scalars, flow mappings
/// and sequences of mappings are intentionally unsupported and raise an error.
public indirect enum YAMLValue: Equatable, Sendable {
    case scalar(String)
    case list([YAMLValue])
    case map([YAMLEntry])

    public subscript(key: String) -> YAMLValue? {
        guard case .map(let entries) = self else { return nil }
        return entries.first { $0.key == key }?.value
    }

    public var string: String? {
        if case .scalar(let s) = self { return s }
        return nil
    }

    /// Scalars of a sequence; a lone scalar is treated as a one-element sequence.
    public var stringList: [String] {
        switch self {
        case .scalar(let s): return s.isEmpty ? [] : [s]
        case .list(let items): return items.compactMap(\.string)
        case .map: return []
        }
    }

    public var entries: [YAMLEntry] {
        if case .map(let entries) = self { return entries }
        return []
    }
}

public struct YAMLEntry: Equatable, Sendable {
    public var key: String
    public var value: YAMLValue
}

public struct YAMLError: Error, CustomStringConvertible {
    public var line: Int
    public var message: String
    public var description: String { "siriready.yaml line \(line): \(message)" }
}

public enum YAML {
    public static func parse(_ text: String) throws -> YAMLValue {
        var lines: [(number: Int, indent: Int, content: String)] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let stripped = stripComment(raw)
            let content = stripped.trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if raw.hasPrefix("\t") { throw YAMLError(line: i + 1, message: "tabs are not allowed for indentation") }
            let indent = stripped.prefix { $0 == " " }.count
            lines.append((i + 1, indent, content))
        }
        var index = 0
        guard !lines.isEmpty else { return .map([]) }
        let value = try parseBlock(lines, &index, indent: lines[0].indent)
        if index < lines.count {
            throw YAMLError(line: lines[index].number, message: "unexpected indentation")
        }
        return value
    }

    private static func parseBlock(_ lines: [(number: Int, indent: Int, content: String)], _ index: inout Int, indent: Int) throws -> YAMLValue {
        if lines[index].content.hasPrefix("- ") || lines[index].content == "-" {
            var items: [YAMLValue] = []
            while index < lines.count, lines[index].indent == indent, lines[index].content.hasPrefix("-") {
                let item = String(lines[index].content.dropFirst()).trimmingCharacters(in: .whitespaces)
                if item.contains(": ") || item.hasSuffix(":") {
                    throw YAMLError(line: lines[index].number, message: "sequences of mappings are not supported")
                }
                items.append(scalarOrInlineList(item))
                index += 1
            }
            return .list(items)
        }
        var entries: [YAMLEntry] = []
        while index < lines.count, lines[index].indent == indent {
            let line = lines[index]
            guard let colon = keySeparator(in: line.content) else {
                throw YAMLError(line: line.number, message: "expected `key: value`")
            }
            let key = unquote(String(line.content[..<colon]).trimmingCharacters(in: .whitespaces))
            let rest = String(line.content[line.content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            index += 1
            if !rest.isEmpty {
                entries.append(YAMLEntry(key: key, value: scalarOrInlineList(rest)))
            } else if index < lines.count, lines[index].indent > indent {
                entries.append(YAMLEntry(key: key, value: try parseBlock(lines, &index, indent: lines[index].indent)))
            } else if index < lines.count, lines[index].indent == indent, lines[index].content.hasPrefix("- ") {
                // Sequences may sit at the same indentation as their key.
                entries.append(YAMLEntry(key: key, value: try parseBlock(lines, &index, indent: indent)))
            } else {
                entries.append(YAMLEntry(key: key, value: .scalar("")))
            }
        }
        return .map(entries)
    }

    private static func keySeparator(in content: String) -> String.Index? {
        var quote: Character?
        for i in content.indices {
            let c = content[i]
            if let q = quote { if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c; continue }
            if c == ":" {
                let next = content.index(after: i)
                if next == content.endIndex || content[next] == " " { return i }
            }
        }
        return nil
    }

    private static func scalarOrInlineList(_ text: String) -> YAMLValue {
        if text.hasPrefix("["), text.hasSuffix("]") {
            let inner = text.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .list([]) }
            return .list(inner.split(separator: ",").map { .scalar(unquote($0.trimmingCharacters(in: .whitespaces))) })
        }
        return .scalar(unquote(text))
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, let f = s.first, let l = s.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for i in line.indices {
            let c = line[i]
            if let q = quote { if c == q { quote = nil } } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#", previous == " " || i == line.startIndex {
                return String(line[..<i])
            }
            previous = c
        }
        return line
    }
}
