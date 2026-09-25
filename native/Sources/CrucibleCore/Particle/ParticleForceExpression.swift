/// A force somebody writes themselves.
///
/// Every other force in the field is one somebody thought of in advance: gravity, a vortex, an attractor,
/// wind. This is the escape hatch — two short pieces of arithmetic, one for each direction, worked out for
/// every body from where it is and how fast it is going. `sin(y * 4) * 2` is a standing wave.
/// `-vy * 0.3` is drag that only acts vertically. `r < 0.3 ? 0 : 1` is not available, because there are no
/// comparisons, but `(x - 0.5) / r` is a push straight outward from the middle.
///
/// ## Compiled once, not read for every body
///
/// This is the part that matters, and it is where the reference implementation this was merged from goes
/// wrong badly enough to be worth describing. Its version parses the text into a tree and then walks that
/// tree for every body, on every axis, on every frame — and each walk trims a string, looks the result up
/// in a dictionary, and allocates a fresh array for every function call in the expression. At sixty-five
/// thousand bodies that is millions of small allocations a second, for arithmetic that amounts to a dozen
/// operations.
///
/// Here the text is turned once into a flat list of steps, and evaluating it is a loop over that list with
/// a small stack of numbers. No allocation, no lookups, nothing recursive. The whole compiled form is a
/// handful of bytes and it is the same work a hand-written formula would be.
///
/// ## Coordinates
///
/// `x` and `y` run from nought to one across the field, not in pixels, so an expression means the same
/// thing whichever way the phone is held and on any screen. `vx` and `vy` are the real speeds. `r` is the
/// distance from the middle, nought at the centre and about seven tenths at a corner. `t` is seconds.
public struct ParticleForceExpression: Sendable, Hashable {
    /// One step of the compiled form.
    ///
    /// A flat list of these *is* the expression, in the order the arithmetic happens — the same order
    /// somebody would work it out on paper, left to right with the brackets already resolved. Evaluating
    /// is pushing numbers onto a small stack and combining them.
    enum Step: Sendable, Hashable {
        case constant(Double)
        case variable(Variable)
        case add
        case subtract
        case multiply
        case divide
        case negate
        case call1(Function1)
        case call2(Function2)
    }

    /// What an expression can read.
    public enum Variable: String, Sendable, Hashable, CaseIterable {
        /// Sideways position, nought to one across the field.
        case x
        /// Vertical position, nought at the top to one at the bottom.
        case y
        /// Sideways speed, in pixels a tick.
        case vx
        /// Vertical speed.
        case vy
        /// Seconds since the field started.
        case t
        /// Distance from the middle of the field, nought to about seven tenths.
        case r
        /// Three and a bit.
        case pi
    }

    /// The one-argument functions.
    public enum Function1: String, Sendable, Hashable, CaseIterable {
        case sin
        case cos
        case abs
        case sqrt
        case sign
        /// Rounds toward nought.
        case floor
        /// The fractional part, always between nought and one.
        case frac
    }

    /// The two-argument functions.
    public enum Function2: String, Sendable, Hashable, CaseIterable {
        case min
        case max
        /// The distance from the origin to a point, which saves writing `sqrt(a*a + b*b)`.
        case hypot
        /// The remainder, always positive — which is what makes it useful for repeating a pattern.
        case wrap
    }

    /// Why an expression could not be used.
    ///
    /// Conforms to `Error` so the reader below can stop where it goes wrong rather than threading a
    /// failure back through every level of the arithmetic by hand.
    public enum Failure: Error, Sendable, Hashable {
        case tooLong(limit: Int)
        case tooComplicated(limit: Int)
        case unexpectedCharacter(Character)
        case unknownName(String)
        case wrongArgumentCount(name: String, wanted: Int, given: Int)
        case expectedSomethingAt(index: Int)
        case unclosedBracket
        case trailingRubbish

        /// Something to show somebody who mistyped.
        ///
        /// Written out rather than left as a code, because the alternative the reference implementation
        /// chose is to turn every mistake into silence: a typo there produces no force and no message, so
        /// the only symptom is that nothing happens.
        public var message: String {
            switch self {
            case .tooLong(let limit):
                return "Too long — keep it under \(limit) characters."
            case .tooComplicated(let limit):
                return "Too complicated — keep it under \(limit) steps."
            case .unexpectedCharacter(let character):
                return "‘\(character)’ does not belong here."
            case .unknownName(let name):
                return "‘\(name)’ is not something this understands."
            case .wrongArgumentCount(let name, let wanted, let given):
                return "‘\(name)’ takes \(wanted) \(wanted == 1 ? "number" : "numbers"), not \(given)."
            case .expectedSomethingAt(let index):
                return "Something is missing around character \(index + 1)."
            case .unclosedBracket:
                return "A bracket was opened and never closed."
            case .trailingRubbish:
                return "There is something extra on the end."
            }
        }
    }

    /// How long an expression may be.
    public static let characterLimit = 120
    /// How many steps it may compile to.
    ///
    /// Generous relative to the character limit, so the limit somebody meets is the one about length. It
    /// exists so that a pathological expression cannot make the per-body loop arbitrarily long.
    public static let stepLimit = 160

    /// The compiled steps.
    let steps: [Step]
    /// What was typed, kept so it can be shown back.
    public let source: String

    /// Nothing at all — no force. What an empty box means.
    ///
    /// Named `blank` rather than `none` so it cannot be confused with an optional's own empty case, which
    /// makes `Result<ParticleForceExpression, _>.success(.none)` ambiguous at the point of use.
    public static let blank = ParticleForceExpression(steps: [], source: "")

    /// Whether this does anything.
    public var isEmpty: Bool { steps.isEmpty }

    init(steps: [Step], source: String) {
        self.steps = steps
        self.source = source
    }

    /// Turns text into something that can be evaluated, or says why it cannot.
    ///
    /// An empty box is not a mistake — it means no force — so it compiles to nothing and succeeds.
    public static func compile(_ text: String) -> Result<ParticleForceExpression, Failure> {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return .success(.blank) }
        guard trimmed.count <= characterLimit else {
            return .failure(.tooLong(limit: characterLimit))
        }

        var parser = Parser(Array(trimmed))
        do {
            try parser.parseExpression()
            guard parser.atEnd else { throw Failure.trailingRubbish }
            guard parser.steps.count <= stepLimit else {
                throw Failure.tooComplicated(limit: stepLimit)
            }
            return .success(ParticleForceExpression(steps: parser.steps, source: trimmed))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.trailingRubbish)
        }
    }

    /// Everything an expression can read, for one body at one moment.
    public struct Inputs: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var velocityX: Double
        public var velocityY: Double
        public var time: Double
        public var radius: Double

        public init(
            x: Double,
            y: Double,
            velocityX: Double,
            velocityY: Double,
            time: Double,
            radius: Double
        ) {
            self.x = x
            self.y = y
            self.velocityX = velocityX
            self.velocityY = velocityY
            self.time = time
            self.radius = radius
        }
    }

    /// Works out the value for one body.
    ///
    /// Anything that cannot produce a usable number gives nought rather than spreading through the
    /// simulation: dividing by nothing, the square root of a negative, a result too large to hold. That is
    /// a force of nought at that instant, which is visible as the body not being pushed — far better than
    /// a body whose position becomes meaningless and takes its neighbours with it.
    public func value(for inputs: Inputs) -> Double {
        guard !steps.isEmpty else { return 0 }

        // Borrowed from the call stack rather than allocated. This runs twice per body per tick, and an
        // ordinary array here means a heap allocation every time — measured at twenty-five thousand
        // bodies that was most of the fourteen milliseconds the whole pass cost, for arithmetic worth a
        // dozen operations. Thirty-two deep is plenty: the step limit bounds how deeply brackets can nest
        // long before the stack could fill.
        return withUnsafeTemporaryAllocation(of: Double.self, capacity: 32) { stack in
            evaluate(steps: steps, into: stack, inputs: inputs)
        }
    }

    /// The loop itself, given somewhere to keep its working numbers.
    private func evaluate(
        steps: [Step],
        into stack: UnsafeMutableBufferPointer<Double>,
        inputs: Inputs
    ) -> Double {
        var depth = 0

        @inline(__always)
        func push(_ value: Double) {
            guard depth < stack.count else { return }
            stack[depth] = value.isFinite ? value : 0
            depth += 1
        }

        @inline(__always)
        func pop() -> Double {
            guard depth > 0 else { return 0 }
            depth -= 1
            return stack[depth]
        }

        for step in steps {
            switch step {
            case .constant(let value):
                push(value)
            case .variable(let variable):
                switch variable {
                case .x: push(inputs.x)
                case .y: push(inputs.y)
                case .vx: push(inputs.velocityX)
                case .vy: push(inputs.velocityY)
                case .t: push(inputs.time)
                case .r: push(inputs.radius)
                case .pi: push(3.141592653589793)
                }
            case .add:
                let right = pop()
                push(pop() + right)
            case .subtract:
                let right = pop()
                push(pop() - right)
            case .multiply:
                let right = pop()
                push(pop() * right)
            case .divide:
                let right = pop()
                let left = pop()
                // Nought rather than infinity. Infinity multiplied by nought is not a number, and one
                // body holding one of those spreads it to every body it touches.
                push(right == 0 ? 0 : left / right)
            case .negate:
                push(-pop())
            case .call1(let function):
                let argument = pop()
                switch function {
                case .sin: push(jsSin(argument))
                case .cos: push(jsCos(argument))
                case .abs: push(abs(argument))
                // Clamped at nought rather than refusing, so `sqrt(x - 0.5)` is usable across the whole
                // field instead of producing nothing over half of it.
                case .sqrt: push(argument < 0 ? 0 : argument.squareRoot())
                case .sign: push(argument > 0 ? 1 : (argument < 0 ? -1 : 0))
                case .floor: push(argument.rounded(.down))
                case .frac: push(argument - argument.rounded(.down))
                }
            case .call2(let function):
                let second = pop()
                let first = pop()
                switch function {
                case .min: push(Swift.min(first, second))
                case .max: push(Swift.max(first, second))
                case .hypot: push((first * first + second * second).squareRoot())
                case .wrap:
                    guard second != 0 else {
                        push(0)
                        continue
                    }
                    let remainder = first.truncatingRemainder(dividingBy: second)
                    push(remainder < 0 ? remainder + abs(second) : remainder)
                }
            }
        }

        let result = depth > 0 ? stack[depth - 1] : 0
        return result.isFinite ? result : 0
    }

    // MARK: - Turning text into steps

    /// A plain recursive-descent reader, which is the right shape for arithmetic: one level for adding,
    /// one for multiplying, one for signs, one for brackets and names.
    private struct Parser {
        let characters: [Character]
        var position = 0
        var steps: [Step] = []

        init(_ characters: [Character]) {
            self.characters = characters
        }

        /// Whether everything has been read.
        ///
        /// Does not move the position: a check has no business changing where the reader is, and the
        /// compiler enforces that here because the property is not marked as changing anything.
        var atEnd: Bool {
            var scan = position
            while scan < characters.count, characters[scan] == " " || characters[scan] == "\t" {
                scan += 1
            }
            return scan >= characters.count
        }

        mutating func skipSpace() {
            while position < characters.count, characters[position] == " " || characters[position] == "\t" {
                position += 1
            }
        }

        func peek() -> Character? {
            var scan = position
            while scan < characters.count, characters[scan] == " " || characters[scan] == "\t" {
                scan += 1
            }
            return scan < characters.count ? characters[scan] : nil
        }

        mutating func take(_ expected: Character) -> Bool {
            skipSpace()
            guard position < characters.count, characters[position] == expected else { return false }
            position += 1
            return true
        }

        mutating func emit(_ step: Step) throws {
            guard steps.count < ParticleForceExpression.stepLimit else {
                throw Failure.tooComplicated(limit: ParticleForceExpression.stepLimit)
            }
            steps.append(step)
        }

        /// Adding and subtracting, which bind least tightly.
        ///
        /// The operator is taken with `take`, which moves past the spaces *and* the symbol. Advancing the
        /// position by one after looking ahead — which is the obvious way to write this — moves past the
        /// space and leaves the symbol still there, so the next thing read is the operator itself and
        /// nothing after a space parses at all. `2 + 3 * 4` was refused outright, and `0 - 2` came out as
        /// positive two, because the minus was read twice: once as a subtraction and once as a sign.
        mutating func parseExpression() throws {
            try parseTerm()
            while true {
                if take("+") {
                    try parseTerm()
                    try emit(.add)
                } else if take("-") {
                    try parseTerm()
                    try emit(.subtract)
                } else {
                    return
                }
            }
        }

        /// Multiplying and dividing.
        mutating func parseTerm() throws {
            try parseSigned()
            while true {
                if take("*") {
                    try parseSigned()
                    try emit(.multiply)
                } else if take("/") {
                    try parseSigned()
                    try emit(.divide)
                } else {
                    return
                }
            }
        }

        /// A leading plus or minus.
        mutating func parseSigned() throws {
            skipSpace()
            if take("-") {
                try parseSigned()
                try emit(.negate)
                return
            }
            if take("+") {
                try parseSigned()
                return
            }
            try parseAtom()
        }

        /// A number, a bracket, a name, or a call.
        mutating func parseAtom() throws {
            skipSpace()
            guard position < characters.count else {
                throw Failure.expectedSomethingAt(index: position)
            }
            let character = characters[position]

            if character == "(" {
                position += 1
                try parseExpression()
                guard take(")") else { throw Failure.unclosedBracket }
                return
            }

            if character.isNumber || character == "." {
                try parseNumber()
                return
            }

            if character.isLetter {
                try parseName()
                return
            }

            throw Failure.unexpectedCharacter(character)
        }

        mutating func parseNumber() throws {
            var text = ""
            var seenDot = false
            while position < characters.count {
                let character = characters[position]
                if character.isNumber {
                    text.append(character)
                } else if character == ".", !seenDot {
                    seenDot = true
                    text.append(character)
                } else {
                    break
                }
                position += 1
            }
            // No exponent notation. Deliberate: `1e3` would otherwise read as `1` followed by a name
            // `e3`, which fails with a confusing message about an unknown name — and in an expression of
            // a hundred characters nobody needs it.
            guard let value = Double(text), value.isFinite else {
                throw Failure.unexpectedCharacter(characters[min(position, characters.count - 1)])
            }
            try emit(.constant(value))
        }

        mutating func parseName() throws {
            var name = ""
            while position < characters.count,
                  characters[position].isLetter || characters[position].isNumber
            {
                name.append(characters[position])
                position += 1
            }
            let lowered = name.lowercased()

            // A name followed by a bracket is a call.
            if peek() == "(" {
                position += 1
                var arguments = 0
                if peek() == ")" {
                    position += 1
                } else {
                    repeat {
                        try parseExpression()
                        arguments += 1
                    } while take(",")
                    guard take(")") else { throw Failure.unclosedBracket }
                }

                if let function = Function1(rawValue: lowered) {
                    guard arguments == 1 else {
                        throw Failure.wrongArgumentCount(name: lowered, wanted: 1, given: arguments)
                    }
                    try emit(.call1(function))
                    return
                }
                if let function = Function2(rawValue: lowered) {
                    guard arguments == 2 else {
                        throw Failure.wrongArgumentCount(name: lowered, wanted: 2, given: arguments)
                    }
                    try emit(.call2(function))
                    return
                }
                throw Failure.unknownName(lowered)
            }

            guard let variable = Variable(rawValue: lowered) else {
                throw Failure.unknownName(lowered)
            }
            try emit(.variable(variable))
        }
    }
}

extension String {
    /// The string without leading or trailing whitespace.
    ///
    /// By hand, because this module has no Foundation.
    var trimmed: String {
        var view = Substring(self)
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        while let last = view.last, last.isWhitespace { view = view.dropLast() }
        return String(view)
    }
}

// MARK: - Applying it

/// A pair of expressions, one for each direction, and what they do to the swarm.
public final class SwarmCustomForce {
    public init() {}

    /// Pushes every body by whatever the two expressions say.
    public func step(
        swarm: Swarm,
        acrossward: ParticleForceExpression,
        downward: ParticleForceExpression,
        strength: Double,
        width: Double,
        height: Double,
        time: Double
    ) {
        let bodies = swarm.count
        guard bodies > 0, width > 0, height > 0 else { return }
        guard !acrossward.isEmpty || !downward.isEmpty else { return }
        let scale = strength.isFinite ? strength : 0
        guard scale != 0 else { return }

        let positions = swarm.positions
        let velocities = swarm.velocities
        let when = time.isFinite ? time : 0
        let inverseWidth = 1 / width
        let inverseHeight = 1 / height

        for index in 0 ..< bodies {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            let velX = Double(velocities[pair])
            let velY = Double(velocities[pair + 1])
            guard x.isFinite, y.isFinite, velX.isFinite, velY.isFinite else { continue }

            // Nought to one across the field rather than pixels, so an expression means the same thing
            // whichever way the phone is held and on any screen.
            let acrossFraction = x * inverseWidth
            let downFraction = y * inverseHeight
            let fromCentreX = acrossFraction - 0.5
            let fromCentreY = downFraction - 0.5

            let inputs = ParticleForceExpression.Inputs(
                x: acrossFraction,
                y: downFraction,
                velocityX: velX,
                velocityY: velY,
                time: when,
                radius: (fromCentreX * fromCentreX + fromCentreY * fromCentreY).squareRoot()
            )

            let pushX = acrossward.isEmpty ? 0 : acrossward.value(for: inputs) * scale
            let pushY = downward.isEmpty ? 0 : downward.value(for: inputs) * scale
            guard pushX.isFinite, pushY.isFinite else { continue }

            // Bounded, for the same reason the fluid's push is: an expression somebody typed can ask for
            // any number at all, and a velocity too large to hold becomes infinity, which later meets the
            // speed limit and turns into not-a-number. A limit means a wild expression looks wrong rather
            // than destroying the field.
            let limit = Self.pushLimit
            let asked = (pushX * pushX + pushY * pushY).squareRoot()
            let factor = asked > limit ? limit / asked : 1
            velocities[pair] = JS.toFloat32(velX + pushX * factor)
            velocities[pair + 1] = JS.toFloat32(velY + pushY * factor)
        }
    }

    /// The most a written force may change one body's velocity by in one tick.
    ///
    /// Sixty, twice the field's default speed limit — so an expression can always overcome a body
    /// travelling at full speed, and can never ask for something with no sensible size.
    public static let pushLimit = 60.0
}
