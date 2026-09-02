import CoreGraphics

/// Official Grok icon (SpaceXAI). From https://grok.com/images/favicon.svg
public enum GrokMark {
    public static let viewBox: CGFloat = 512

    private static let pathData = [
        "M210.484 312.759L343.465 210.383C349.984 205.364 359.302 207.322 362.408 215.117C378.758 256.231 371.454 305.64 338.925 339.563C306.397 373.487 261.137 380.927 219.768 363.983L174.577 385.803C239.394 432.008 318.104 420.581 367.289 369.251C406.303 328.564 418.386 273.104 407.088 223.091L407.19 223.198C390.807 149.726 411.218 120.359 453.03 60.3072C454.02 58.8833 455.01 57.4595 456 56L400.978 113.382V113.204L210.45 312.794",
        "M183.042 337.641C136.519 291.294 144.54 219.567 184.236 178.203C213.59 147.59 261.683 135.096 303.666 153.464L348.755 131.75C340.632 125.627 330.221 119.042 318.275 114.414C264.277 91.2407 199.63 102.774 155.735 148.516C113.513 192.549 100.236 260.254 123.036 318.027C140.069 361.206 112.148 391.748 84.0229 422.575C74.0561 433.503 64.0553 444.431 56 456L183.007 337.677",
    ]

    public static func cgPath() -> CGPath {
        let path = CGMutablePath()
        for d in pathData {
            append(d, to: path)
        }
        return path
    }

    static func append(_ d: String, to path: CGMutablePath) {
        let tokens = tokenize(d)
        var i = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastCommand: Character = "M"
        var subpathOpen = false

        func nextNumber() -> CGFloat {
            guard i < tokens.count, case .number(let value) = tokens[i] else {
                return 0
            }
            i += 1
            return value
        }

        func hasNumber() -> Bool {
            guard i < tokens.count else { return false }
            if case .number = tokens[i] { return true }
            return false
        }

        while i < tokens.count {
            let command: Character
            if case .command(let c) = tokens[i] {
                i += 1
                command = c
            } else if hasNumber() {
                switch lastCommand {
                case "M": command = "L"
                case "m": command = "l"
                default: command = lastCommand
                }
            } else {
                i += 1
                continue
            }
            lastCommand = command

            switch command {
            case "M", "m":
                let rel = command == "m"
                let nx = nextNumber()
                let ny = nextNumber()
                x = rel ? x + nx : nx
                y = rel ? y + ny : ny
                path.move(to: CGPoint(x: x, y: y))
                startX = x
                startY = y
                subpathOpen = true
            case "L", "l":
                while hasNumber() {
                    let rel = command == "l"
                    let nx = nextNumber()
                    let ny = nextNumber()
                    x = rel ? x + nx : nx
                    y = rel ? y + ny : ny
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            case "H", "h":
                while hasNumber() {
                    let nx = nextNumber()
                    x = command == "h" ? x + nx : nx
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            case "V", "v":
                while hasNumber() {
                    let ny = nextNumber()
                    y = command == "v" ? y + ny : ny
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            case "C", "c":
                while hasNumber() {
                    let rel = command == "c"
                    let x1 = nextNumber()
                    let y1 = nextNumber()
                    let x2 = nextNumber()
                    let y2 = nextNumber()
                    let x3 = nextNumber()
                    let y3 = nextNumber()
                    let p1 = CGPoint(x: rel ? x + x1 : x1, y: rel ? y + y1 : y1)
                    let p2 = CGPoint(x: rel ? x + x2 : x2, y: rel ? y + y2 : y2)
                    let p3 = CGPoint(x: rel ? x + x3 : x3, y: rel ? y + y3 : y3)
                    path.addCurve(to: p3, control1: p1, control2: p2)
                    x = p3.x
                    y = p3.y
                }
            case "Z", "z":
                path.closeSubpath()
                x = startX
                y = startY
                subpathOpen = false
            default:
                break
            }
        }

        if subpathOpen {
            path.closeSubpath()
        }
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," {
                i += 1
                continue
            }
            if c.isLetter {
                tokens.append(.command(c))
                i += 1
                continue
            }

            var text = ""
            if c == "+" || c == "-" {
                text.append(c)
                i += 1
            }
            var seenDot = false
            var seenExp = false
            while i < chars.count {
                let ch = chars[i]
                if ch.isNumber {
                    text.append(ch)
                    i += 1
                } else if ch == "." {
                    if seenDot || seenExp { break }
                    seenDot = true
                    text.append(ch)
                    i += 1
                } else if ch == "e" || ch == "E" {
                    if seenExp { break }
                    seenExp = true
                    text.append(ch)
                    i += 1
                    if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                        text.append(chars[i])
                        i += 1
                    }
                } else if (ch == "+" || ch == "-") && !text.isEmpty && text.last != "e" && text.last != "E" {
                    break
                } else {
                    break
                }
            }
            if let value = Double(text) {
                tokens.append(.number(CGFloat(value)))
            }
        }
        return tokens
    }
}
