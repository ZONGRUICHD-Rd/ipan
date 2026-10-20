import Foundation

/// semi-utils 的模板是「先用 Jinja2 渲染整段 JSON 文本，再 json.loads」。
/// 这里实现模板里用到的 Jinja2 表达式子集，保证 config/templates 下的模板原样可用：
/// 变量/属性/下标/切片、函数调用（vh/vw/auto_logo）、字符串方法（partition/replace/split…）、
/// 过滤器（default/replace/min/max/…）、and/or/not、比较、四则运算、`a if b else c`、列表字面量。
indirect enum JValue {
    case undefined
    case none
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case list([JValue])
    case dict([String: JValue])
    case function(String)

    var truthy: Bool {
        switch self {
        case .undefined, .none: return false
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .list(let l): return !l.isEmpty
        case .dict(let d): return !d.isEmpty
        case .function: return true
        }
    }

    var isUndefined: Bool { if case .undefined = self { return true }; return false }

    /// Python str()
    var str: String {
        switch self {
        case .undefined: return ""
        case .none: return "None"
        case .bool(let b): return b ? "True" : "False"
        case .int(let i): return String(i)
        case .double(let d): return JValue.formatDouble(d)
        case .string(let s): return s
        case .list, .dict: return repr
        case .function(let n): return "<function \(n)>"
        }
    }

    /// Python repr()
    var repr: String {
        switch self {
        case .string(let s):
            return "'" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
        case .list(let l): return "[" + l.map(\.repr).joined(separator: ", ") + "]"
        case .dict(let d): return "{" + d.keys.sorted().map { "'\($0)': \(d[$0]!.repr)" }.joined(separator: ", ") + "}"
        default: return str
        }
    }

    var number: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func formatDouble(_ d: Double) -> String {
        if d.isFinite && d == d.rounded() && abs(d) < 1e16 { return String(Int(d)) + ".0" }
        return String(d)
    }

    static func num(_ d: Double, preferInt: Bool) -> JValue {
        preferInt && d == d.rounded() && abs(d) < 9e15 ? .int(Int(d)) : .double(d)
    }
}

struct TemplateError: Error, CustomStringConvertible {
    let description: String
}

/// 表达式求值时可用的函数（vh / vw / auto_logo）
protocol TemplateFunctions {
    func call(_ name: String, _ args: [JValue], _ kwargs: [String: JValue]) throws -> JValue
}

enum TemplateEngine {
    /// 渲染整段模板文本：替换所有 `{{ … }}`。
    /// 结果会被当作 JSON 解析，而表达式都位于 JSON 字符串内，所以对 `\` 和 `"` 做转义以免破坏 JSON。
    static func render(_ template: String, variables: [String: JValue], functions: TemplateFunctions) throws -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[rest.startIndex..<open.lowerBound]
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else {
                throw TemplateError(description: "未闭合的 {{")
            }
            let source = String(rest[open.upperBound..<close.lowerBound])
            let value = try evaluate(source, variables: variables, functions: functions)
            out += value.str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            rest = rest[close.upperBound...]
        }
        out += rest
        return out
    }

    static func evaluate(_ source: String, variables: [String: JValue], functions: TemplateFunctions) throws -> JValue {
        var parser = ExprParser(tokens: try Lexer.tokenize(source))
        let node = try parser.parseExpression()
        guard parser.atEnd else { throw TemplateError(description: "无法解析表达式: \(source)") }
        return try Evaluator(variables: variables, functions: functions).eval(node)
    }
}

// MARK: - Lexer

enum Token: Equatable {
    case name(String)
    case string(String)
    case int(Int)
    case double(Double)
    case op(String)
}

enum Lexer {
    static func tokenize(_ s: String) throws -> [Token] {
        let chars = Array(s)
        var i = 0
        var tokens: [Token] = []
        let twoCharOps: Set<String> = ["==", "!=", "<=", ">=", "//", "**"]
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                tokens.append(.name(String(chars[i..<j])))
                i = j
                continue
            }
            if c.isNumber {
                var j = i
                var isFloat = false
                while j < chars.count, chars[j].isNumber || (chars[j] == "." && !isFloat && j + 1 < chars.count && chars[j + 1].isNumber) {
                    if chars[j] == "." { isFloat = true }
                    j += 1
                }
                let text = String(chars[i..<j])
                tokens.append(isFloat ? .double(Double(text) ?? 0) : .int(Int(text) ?? 0))
                i = j
                continue
            }
            if c == "'" || c == "\"" {
                var j = i + 1
                var value = ""
                while j < chars.count, chars[j] != c {
                    if chars[j] == "\\", j + 1 < chars.count {
                        let n = chars[j + 1]
                        switch n {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        case "\\", "'", "\"": value.append(n)
                        default: value.append("\\"); value.append(n)
                        }
                        j += 2
                    } else {
                        value.append(chars[j])
                        j += 1
                    }
                }
                guard j < chars.count else { throw TemplateError(description: "未闭合的字符串") }
                tokens.append(.string(value))
                i = j + 1
                continue
            }
            if i + 1 < chars.count, twoCharOps.contains(String(chars[i...i + 1])) {
                tokens.append(.op(String(chars[i...i + 1])))
                i += 2
                continue
            }
            if "()[]{}.,:|+-*/%~<>=".contains(c) {
                tokens.append(.op(String(c)))
                i += 1
                continue
            }
            throw TemplateError(description: "无法识别的字符: \(c)")
        }
        return tokens
    }
}

// MARK: - Parser

indirect enum Expr {
    case literal(JValue)
    case name(String)
    case list([Expr])
    case attr(Expr, String)
    case index(Expr, Expr)
    case slice(Expr, Expr?, Expr?)
    case call(Expr, [Expr], [String: Expr])
    case filter(Expr, String, [Expr], [String: Expr])
    case unary(String, Expr)
    case binary(String, Expr, Expr)
    case conditional(Expr, Expr, Expr?)
}

struct ExprParser {
    let tokens: [Token]
    var pos = 0

    init(tokens: [Token]) { self.tokens = tokens }

    var atEnd: Bool { pos >= tokens.count }
    var peek: Token? { pos < tokens.count ? tokens[pos] : nil }

    mutating func next() -> Token? {
        defer { pos += 1 }
        return peek
    }

    mutating func accept(op: String) -> Bool {
        if peek == .op(op) { pos += 1; return true }
        return false
    }

    mutating func accept(name: String) -> Bool {
        if peek == .name(name) { pos += 1; return true }
        return false
    }

    mutating func expect(op: String) throws {
        guard accept(op: op) else { throw TemplateError(description: "缺少 '\(op)'") }
    }

    mutating func parseExpression() throws -> Expr {
        let value = try parseOr()
        if accept(name: "if") {
            let condition = try parseOr()
            let otherwise: Expr? = accept(name: "else") ? try parseExpression() : nil
            return .conditional(condition, value, otherwise)
        }
        return value
    }

    mutating func parseOr() throws -> Expr {
        var lhs = try parseAnd()
        while accept(name: "or") { lhs = .binary("or", lhs, try parseAnd()) }
        return lhs
    }

    mutating func parseAnd() throws -> Expr {
        var lhs = try parseNot()
        while accept(name: "and") { lhs = .binary("and", lhs, try parseNot()) }
        return lhs
    }

    mutating func parseNot() throws -> Expr {
        if accept(name: "not") { return .unary("not", try parseNot()) }
        return try parseCompare()
    }

    mutating func parseCompare() throws -> Expr {
        var lhs = try parseAdditive()
        while true {
            if case .op(let o)? = peek, ["==", "!=", "<", ">", "<=", ">="].contains(o) {
                pos += 1
                lhs = .binary(o, lhs, try parseAdditive())
            } else if accept(name: "in") {
                lhs = .binary("in", lhs, try parseAdditive())
            } else {
                return lhs
            }
        }
    }

    mutating func parseAdditive() throws -> Expr {
        var lhs = try parseMultiplicative()
        while case .op(let o)? = peek, ["+", "-", "~"].contains(o) {
            pos += 1
            lhs = .binary(o, lhs, try parseMultiplicative())
        }
        return lhs
    }

    mutating func parseMultiplicative() throws -> Expr {
        var lhs = try parseUnary()
        while case .op(let o)? = peek, ["*", "/", "//", "%"].contains(o) {
            pos += 1
            lhs = .binary(o, lhs, try parseUnary())
        }
        return lhs
    }

    mutating func parseUnary() throws -> Expr {
        if accept(op: "-") { return .unary("-", try parseUnary()) }
        if accept(op: "+") { return try parseUnary() }
        return try parseFiltered()
    }

    mutating func parseFiltered() throws -> Expr {
        var value = try parsePostfix()
        while accept(op: "|") {
            guard case .name(let filterName)? = next() else { throw TemplateError(description: "过滤器名缺失") }
            var args: [Expr] = []
            var kwargs: [String: Expr] = [:]
            if accept(op: "(") { (args, kwargs) = try parseArguments() }
            value = .filter(value, filterName, args, kwargs)
        }
        return value
    }

    mutating func parsePostfix() throws -> Expr {
        var value = try parsePrimary()
        while true {
            if accept(op: ".") {
                guard case .name(let n)? = next() else { throw TemplateError(description: "属性名缺失") }
                value = .attr(value, n)
            } else if accept(op: "(") {
                let (args, kwargs) = try parseArguments()
                value = .call(value, args, kwargs)
            } else if accept(op: "[") {
                var start: Expr? = nil
                if peek != .op(":") { start = try parseExpression() }
                if accept(op: ":") {
                    var end: Expr? = nil
                    if peek != .op("]") { end = try parseExpression() }
                    try expect(op: "]")
                    value = .slice(value, start, end)
                } else {
                    try expect(op: "]")
                    guard let start else { throw TemplateError(description: "空下标") }
                    value = .index(value, start)
                }
            } else {
                return value
            }
        }
    }

    /// 已经消费了 "("
    mutating func parseArguments() throws -> ([Expr], [String: Expr]) {
        var args: [Expr] = []
        var kwargs: [String: Expr] = [:]
        if accept(op: ")") { return (args, kwargs) }
        repeat {
            if case .name(let n)? = peek, pos + 1 < tokens.count, tokens[pos + 1] == .op("=") {
                pos += 2
                kwargs[n] = try parseExpression()
            } else {
                args.append(try parseExpression())
            }
        } while accept(op: ",")
        try expect(op: ")")
        return (args, kwargs)
    }

    mutating func parsePrimary() throws -> Expr {
        guard let token = next() else { throw TemplateError(description: "表达式意外结束") }
        switch token {
        case .int(let i): return .literal(.int(i))
        case .double(let d): return .literal(.double(d))
        case .string(let s):
            // 相邻字符串字面量自动拼接
            var s = s
            while case .string(let more)? = peek { s += more; pos += 1 }
            return .literal(.string(s))
        case .name(let n):
            switch n {
            case "true", "True": return .literal(.bool(true))
            case "false", "False": return .literal(.bool(false))
            case "none", "None": return .literal(.none)
            default: return .name(n)
            }
        case .op("("):
            let first = try parseExpression()
            if accept(op: ",") {
                var items = [first]
                while peek != .op(")") {
                    items.append(try parseExpression())
                    if !accept(op: ",") { break }
                }
                try expect(op: ")")
                return .list(items)
            }
            try expect(op: ")")
            return first
        case .op("["):
            var items: [Expr] = []
            while peek != .op("]") {
                items.append(try parseExpression())
                if !accept(op: ",") { break }
            }
            try expect(op: "]")
            return .list(items)
        default:
            throw TemplateError(description: "无法解析的记号: \(token)")
        }
    }
}

// MARK: - Evaluator

struct Evaluator {
    let variables: [String: JValue]
    let functions: TemplateFunctions

    func eval(_ e: Expr) throws -> JValue {
        switch e {
        case .literal(let v): return v
        case .name(let n):
            if let v = variables[n] { return v }
            if ["vh", "vw", "auto_logo", "range"].contains(n) { return .function(n) }
            return .undefined
        case .list(let items): return .list(try items.map(eval))
        case .attr(let base, let name):
            let b = try eval(base)
            switch b {
            case .dict(let d): return d[name] ?? .undefined
            case .undefined: return .undefined
            default: return .function("." + name) // 方法，等待调用
            }
        case .index(let base, let idx):
            return subscriptValue(try eval(base), try eval(idx))
        case .slice(let base, let s, let t):
            return sliceValue(try eval(base), try s.map(eval), try t.map(eval))
        case .call(let callee, let args, let kwargs):
            let a = try args.map(eval)
            var kw: [String: JValue] = [:]
            for (k, v) in kwargs { kw[k] = try eval(v) }
            if case .attr(let base, let method) = callee {
                return try callMethod(try eval(base), method, a)
            }
            guard case .function(let name) = try eval(callee) else { return .undefined }
            if name == "range" {
                let n = Int(a.first?.number ?? 0)
                return .list((0..<max(0, n)).map { .int($0) })
            }
            return try functions.call(name, a, kw)
        case .filter(let base, let name, let args, let kwargs):
            let v = try eval(base)
            let a = try args.map(eval)
            var kw: [String: JValue] = [:]
            for (k, x) in kwargs { kw[k] = try eval(x) }
            return applyFilter(name, v, a, kw)
        case .unary(let op, let operand):
            let v = try eval(operand)
            if op == "not" { return .bool(!v.truthy) }
            if case .int(let i) = v { return .int(-i) }
            return .double(-(v.number ?? 0))
        case .binary(let op, let l, let r):
            if op == "or" {
                let lv = try eval(l)
                return lv.truthy ? lv : try eval(r)
            }
            if op == "and" {
                let lv = try eval(l)
                return lv.truthy ? try eval(r) : lv
            }
            return binary(op, try eval(l), try eval(r))
        case .conditional(let cond, let a, let b):
            if try eval(cond).truthy { return try eval(a) }
            return try b.map(eval) ?? .undefined
        }
    }

    private func normalize(_ i: Int, count: Int) -> Int { i < 0 ? i + count : i }

    func subscriptValue(_ base: JValue, _ idx: JValue) -> JValue {
        switch base {
        case .list(let l):
            guard let n = idx.number else { return .undefined }
            let i = normalize(Int(n), count: l.count)
            return l.indices.contains(i) ? l[i] : .undefined
        case .string(let s):
            guard let n = idx.number else { return .undefined }
            let chars = Array(s)
            let i = normalize(Int(n), count: chars.count)
            return chars.indices.contains(i) ? .string(String(chars[i])) : .undefined
        case .dict(let d):
            return d[idx.str] ?? .undefined
        default:
            return .undefined
        }
    }

    func sliceValue(_ base: JValue, _ s: JValue?, _ t: JValue?) -> JValue {
        func bounds(_ count: Int) -> Range<Int> {
            var a = s.flatMap { $0.number }.map { Int($0) } ?? 0
            var b = t.flatMap { $0.number }.map { Int($0) } ?? count
            if a < 0 { a += count }
            if b < 0 { b += count }
            a = min(max(a, 0), count)
            b = min(max(b, 0), count)
            return a..<max(a, b)
        }
        switch base {
        case .string(let str):
            let chars = Array(str)
            return .string(String(chars[bounds(chars.count)]))
        case .list(let l):
            return .list(Array(l[bounds(l.count)]))
        case .undefined:
            return .string("")
        default:
            let chars = Array(base.str)
            return .string(String(chars[bounds(chars.count)]))
        }
    }

    func callMethod(_ base: JValue, _ method: String, _ args: [JValue]) throws -> JValue {
        if case .dict(let d) = base {
            switch method {
            case "get": return d[args.first?.str ?? ""] ?? (args.count > 1 ? args[1] : .none)
            case "keys": return .list(d.keys.sorted().map { .string($0) })
            default: return .undefined
            }
        }
        if case .list(let l) = base {
            switch method {
            case "index":
                let target = args.first?.str ?? ""
                return .int(l.firstIndex { $0.str == target } ?? -1)
            case "count": return .int(l.filter { $0.str == args.first?.str }.count)
            default: return .undefined
            }
        }
        guard case .string(let s) = base else {
            if base.isUndefined { throw TemplateError(description: "对未定义的值调用 \(method)()") }
            return .undefined
        }
        switch method {
        case "partition":
            let sep = args.first?.str ?? ""
            if !sep.isEmpty, let r = s.range(of: sep) {
                return .list([.string(String(s[..<r.lowerBound])), .string(sep), .string(String(s[r.upperBound...]))])
            }
            return .list([.string(s), .string(""), .string("")])
        case "rpartition":
            let sep = args.first?.str ?? ""
            if !sep.isEmpty, let r = s.range(of: sep, options: .backwards) {
                return .list([.string(String(s[..<r.lowerBound])), .string(sep), .string(String(s[r.upperBound...]))])
            }
            return .list([.string(""), .string(""), .string(s)])
        case "replace":
            guard args.count >= 2 else { return base }
            let old = args[0].str
            if old.isEmpty { return base }
            return .string(s.replacingOccurrences(of: old, with: args[1].str))
        case "split":
            if let sep = args.first, !sep.isUndefined, case .string(let sepStr) = sep {
                return .list(s.components(separatedBy: sepStr).map { .string($0) })
            }
            return .list(s.split(whereSeparator: { $0.isWhitespace }).map { .string(String($0)) })
        case "strip": return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
        case "lstrip": return .string(String(s.drop(while: { $0.isWhitespace })))
        case "rstrip":
            var t = s
            while t.last?.isWhitespace == true { t.removeLast() }
            return .string(t)
        case "upper": return .string(s.uppercased())
        case "lower": return .string(s.lowercased())
        case "title", "capitalize": return .string(s.capitalized)
        case "startswith": return .bool(s.hasPrefix(args.first?.str ?? ""))
        case "endswith": return .bool(s.hasSuffix(args.first?.str ?? ""))
        case "find":
            guard let r = s.range(of: args.first?.str ?? "") else { return .int(-1) }
            return .int(s.distance(from: s.startIndex, to: r.lowerBound))
        case "join":
            if case .list(let items)? = args.first { return .string(items.map(\.str).joined(separator: s)) }
            return .string("")
        case "format":
            var result = s
            for a in args {
                if let r = result.range(of: "{}") { result.replaceSubrange(r, with: a.str) }
            }
            return .string(result)
        default:
            return .undefined
        }
    }

    func applyFilter(_ name: String, _ v: JValue, _ args: [JValue], _ kw: [String: JValue]) -> JValue {
        switch name {
        case "default", "d":
            let fallback = args.first ?? kw["default_value"] ?? .string("")
            let boolean = (args.count > 1 ? args[1] : kw["boolean"])?.truthy ?? false
            if v.isUndefined || (boolean && !v.truthy) { return fallback }
            return v
        case "replace":
            guard args.count >= 2 else { return v }
            let s = v.str
            let old = args[0].str
            return .string(old.isEmpty ? s : s.replacingOccurrences(of: old, with: args[1].str))
        case "min", "max":
            guard case .list(let l) = v, !l.isEmpty else { return .undefined }
            let picked = l.enumerated().min { a, b in
                let x = a.element.number ?? 0, y = b.element.number ?? 0
                return name == "min" ? x < y : x > y
            }
            return picked?.element ?? .undefined
        case "upper": return .string(v.str.uppercased())
        case "lower": return .string(v.str.lowercased())
        case "trim": return .string(v.str.trimmingCharacters(in: .whitespacesAndNewlines))
        case "string": return .string(v.str)
        case "int": return .int(Int(v.number ?? Double(args.first?.number ?? 0)))
        case "float": return .double(v.number ?? args.first?.number ?? 0)
        case "abs":
            if case .int(let i) = v { return .int(abs(i)) }
            return .double(abs(v.number ?? 0))
        case "round":
            let precision = Int(args.first?.number ?? 0)
            let p = pow(10, Double(precision))
            return .double(((v.number ?? 0) * p).rounded() / p)
        case "length", "count":
            switch v {
            case .list(let l): return .int(l.count)
            case .dict(let d): return .int(d.count)
            default: return .int(v.str.count)
            }
        case "first":
            if case .list(let l) = v { return l.first ?? .undefined }
            return v.str.first.map { .string(String($0)) } ?? .undefined
        case "last":
            if case .list(let l) = v { return l.last ?? .undefined }
            return v.str.last.map { .string(String($0)) } ?? .undefined
        case "join":
            let sep = args.first?.str ?? ""
            if case .list(let l) = v { return .string(l.map(\.str).joined(separator: sep)) }
            return .string(v.str)
        case "truncate":
            let n = Int(args.first?.number ?? 255)
            let s = v.str
            return .string(s.count > n ? String(s.prefix(n)) + "..." : s)
        default:
            return v
        }
    }

    func binary(_ op: String, _ l: JValue, _ r: JValue) -> JValue {
        switch op {
        case "==": return .bool(l.str == r.str && l.repr == r.repr)
        case "!=": return .bool(!(l.str == r.str && l.repr == r.repr))
        case "<", ">", "<=", ">=":
            if let a = l.number, let b = r.number {
                switch op {
                case "<": return .bool(a < b)
                case ">": return .bool(a > b)
                case "<=": return .bool(a <= b)
                default: return .bool(a >= b)
                }
            }
            let a = l.str, b = r.str
            switch op {
            case "<": return .bool(a < b)
            case ">": return .bool(a > b)
            case "<=": return .bool(a <= b)
            default: return .bool(a >= b)
            }
        case "in":
            switch r {
            case .list(let items): return .bool(items.contains { $0.repr == l.repr })
            case .dict(let d): return .bool(d[l.str] != nil)
            default: return .bool(r.str.contains(l.str))
            }
        case "~": return .string(l.str + r.str)
        case "+":
            if case .string(let a) = l, case .string(let b) = r { return .string(a + b) }
            if case .list(let a) = l, case .list(let b) = r { return .list(a + b) }
            return arithmetic(op, l, r)
        default:
            return arithmetic(op, l, r)
        }
    }

    private func arithmetic(_ op: String, _ l: JValue, _ r: JValue) -> JValue {
        let bothInt: Bool = {
            if case .int = l, case .int = r { return true }
            return false
        }()
        let a = l.number ?? 0, b = r.number ?? 0
        switch op {
        case "+": return JValue.num(a + b, preferInt: bothInt)
        case "-": return JValue.num(a - b, preferInt: bothInt)
        case "*": return JValue.num(a * b, preferInt: bothInt)
        case "/": return .double(b == 0 ? 0 : a / b)
        case "//": return JValue.num(b == 0 ? 0 : (a / b).rounded(.down), preferInt: bothInt)
        case "%":
            guard b != 0 else { return .int(0) }
            let m = a - b * (a / b).rounded(.down)
            return JValue.num(m, preferInt: bothInt)
        default: return .undefined
        }
    }
}
