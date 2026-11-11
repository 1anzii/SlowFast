// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

// Only replace explicitly named settings; preserve comments, profiles and unrelated options.
enum ConfigEditing {
    private static func profile(_ line: String) -> String? {
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return nil }
        return String(line[line.index(after: line.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
    }

    static func value(_ key: String, in text: String, globalOnly: Bool = false) -> String? {
        var result: String?
        var inProfile = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let name = profile(trimmed) { inProfile = name != "default"; continue }
            guard !(globalOnly && inProfile), !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: "="),
                  trimmed[..<split].trimmingCharacters(in: .whitespaces) == key else { continue }
            result = String(trimmed[trimmed.index(after: split)...]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    static func setting(_ values: [String: String], in text: String, beforeProfiles: Bool = false) throws -> String {
        guard values.allSatisfy({ !$0.key.contains("\n") && !$0.value.contains("\n") && !$0.value.contains("\r") }) else {
            throw SlowFastError("配置包含无效换行")
        }
        var lines = text.components(separatedBy: "\n")
        var inProfile = false
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let name = profile(trimmed) { inProfile = name != "default"; return false }
            guard !(beforeProfiles && inProfile), !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: "=") else { return false }
            return values[String(trimmed[..<split]).trimmingCharacters(in: .whitespaces)] != nil
        }
        let entries = values.keys.sorted().map { "\($0)=\(values[$0]!)" }
        let index = beforeProfiles ? (lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count) : lines.count
        lines.insert(contentsOf: ["# SlowFast local connection"] + entries + [""], at: index)
        return lines.joined(separator: "\n")
    }
}
