/// Turning what the phone can sense about the room into things the worlds already understand.
///
/// ## Why the phone's other senses are worth anything here
///
/// Tilt and the microphone were the only two the app used, and both are obvious. The rest are not obvious at all, which
/// is the point: the weather changing, how far somebody has walked, where the sun is, how bright the room is. None of
/// them needs any new physics — each lands on something the worlds have always had. The air pressure becomes the room's
/// temperature and the wind, because falling pressure is weather coming in. Steps become a slow tide's strength, because
/// a tide is a slow thing and so is a day's walking. The sun becomes which way the wind blows and how bright the
/// picture is. A dark room becomes a dark world.
///
/// So this is a set of conversions, each one a line or two of arithmetic with a reason. Kept here rather than in the app
/// because a conversion is exactly the kind of thing that is wrong by a factor of ten and looks fine, and because the
/// app cannot be tested.
public enum WorldSenses {
    // MARK: - The weather, from the air pressure

    /// Ordinary air pressure at sea level, in hectopascals — what a barometer calls 1013.
    public static let ordinaryPressure = 1_013.25
    /// How far from ordinary the pressure is taken to be as far as it goes: a deep storm reads about forty below.
    public static let pressureSpan = 40.0

    /// How settled the weather is, from minus one — a deep low, a storm coming — through nought for ordinary, to one for
    /// a high and settled day.
    ///
    /// A phone reads the pressure where it is, which includes how high up it is: a reading taken upstairs is lower than
    /// the same weather downstairs, and on a hill lower again. So this is only meaningful as a *change*, which is why
    /// the app watches it move rather than trusting one reading — see ``weatherDrift(from:to:)``.
    public static func weather(pressure: Double) -> Double {
        guard pressure.isFinite, pressure > 0 else { return 0 }
        return max(-1, min(1, (pressure - ordinaryPressure) / pressureSpan))
    }

    /// How much the weather has changed between two readings, from minus one — falling fast, a storm on the way — to one.
    ///
    /// Over a tenth of ordinary's span, because that is what a barometer calls a change worth mentioning: three or four
    /// hectopascals in a few hours is weather turning.
    public static func weatherDrift(from first: Double, to second: Double) -> Double {
        guard first.isFinite, second.isFinite else { return 0 }
        return max(-1, min(1, (second - first) / (pressureSpan / 10)))
    }

    /// The room's temperature to set from the weather, in Celsius: a settled high is warm, a storm is cold.
    ///
    /// Around twenty, which is what the worlds start at, and never far enough either way to change what materials do —
    /// water does not freeze and nothing melts. It is weather, not a kiln.
    public static func roomTemperature(weather: Double) -> Double {
        let settled = weather.isFinite ? max(-1, min(1, weather)) : 0
        return 20 + settled * 8
    }

    /// The wind to set from the weather turning, in the units the powder world measures wind in.
    ///
    /// Falling pressure means wind; rising means it dying away. The direction follows the sign, so a passing front
    /// reverses it, which is what a front does.
    public static func wind(weatherDrift: Double) -> Double {
        let turning = weatherDrift.isFinite ? max(-1, min(1, weatherDrift)) : 0
        // Five is as hard as the world's own wind setting goes.
        return -turning * 5
    }

    // MARK: - The tide, from how far somebody has walked

    /// How many steps in a day count as a full tide.
    public static let stepsForAFullTide = 10_000.0

    /// How strong the sea's tide should be from the day's steps: nothing at all before a hundred, rising to the
    /// strongest a tide goes at ten thousand.
    ///
    /// A day's walking and a tide are both slow, which is the only reason this is not a gimmick: somebody who walks to
    /// work finds the sea higher when they arrive.
    public static func tideStrength(steps: Int) -> Double {
        guard steps > 100 else { return 0 }
        let share = min(1, Double(steps) / stepsForAFullTide)
        // Two to sixty, which is the range the tide itself accepts.
        return 2 + share * 58
    }

    // MARK: - The sun

    /// Where the sun is, given the hour of the day in a place's own time: minus one is dawn in the east, nought is noon
    /// overhead, one is dusk in the west. Nothing at night.
    ///
    /// Worked out from the clock rather than from where anybody is, on purpose: it needs no permission, cannot be wrong
    /// about somebody's whereabouts, and is right to within the half hour anywhere that keeps sensible time.
    public static func sun(hour: Double) -> Double? {
        guard hour.isFinite, hour >= 0, hour < 24 else { return nil }
        // Six to eighteen: the hours anybody would call daylight, whatever the season.
        guard hour >= 6, hour <= 18 else { return nil }
        return (hour - 12) / 6
    }

    /// Which way and how hard the wind blows from where the sun is — the sun drags the day's weather across the sky
    /// from east to west.
    public static func wind(sun: Double?) -> Double {
        guard let sun, sun.isFinite else { return 0 }
        return max(-3, min(3, sun * 3))
    }

    // MARK: - How bright the room is

    /// How bright the picture should be, from how bright the room is as the phone's own screen brightness reports it.
    ///
    /// Not a light sensor: an app may not read one. The phone's brightness follows the room when it is set to, which is
    /// how it is set by default — so this is the room, at one remove, for nothing.
    ///
    /// Never below a third: a world nobody can see is not a dark room, it is a fault. And never above one, because the
    /// picture is already as bright as the screen goes.
    public static func pictureBrightness(screen: Double) -> Double {
        guard screen.isFinite else { return 1 }
        return max(0.34, min(1, 0.34 + max(0, min(1, screen)) * 0.66))
    }

    /// Whether the room is dark enough that the lab should hold itself back to what is comfortable to look at: no glow,
    /// no flashes, the quieter picture.
    public static func isDarkRoom(screen: Double) -> Bool {
        screen.isFinite && screen < 0.25
    }
}
