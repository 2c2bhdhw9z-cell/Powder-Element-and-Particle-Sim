import Testing

@testable import CrucibleCore

/// The phone's other senses, turned into things the worlds understand.
@Suite("The weather, the day's walking, the sun and the room")
struct WorldSensesTests {
    @Test("Ordinary pressure is ordinary weather, a storm is the far end, and nonsense is neither")
    func readsTheWeather() {
        #expect(WorldSenses.weather(pressure: WorldSenses.ordinaryPressure) == 0)
        #expect(WorldSenses.weather(pressure: 1_033) > 0.4)
        #expect(WorldSenses.weather(pressure: 985) < -0.6)
        // However far out the reading, it never means more than "as settled as it gets" or "as stormy".
        #expect(WorldSenses.weather(pressure: 1_200) == 1)
        #expect(WorldSenses.weather(pressure: 700) == -1)
        #expect(WorldSenses.weather(pressure: .nan) == 0)
        #expect(WorldSenses.weather(pressure: 0) == 0)
    }

    @Test("Pressure falling is weather coming in: colder, and windier")
    func turningWeather() {
        // Four hectopascals down is a front arriving.
        let falling = WorldSenses.weatherDrift(from: 1_013, to: 1_009)
        #expect(falling == -1, "\(falling)")
        let rising = WorldSenses.weatherDrift(from: 1_009, to: 1_013)
        #expect(rising == 1)
        #expect(WorldSenses.weatherDrift(from: 1_013, to: 1_011) == -0.5)
        #expect(WorldSenses.weatherDrift(from: 1_013, to: 1_013) == 0)
        #expect(WorldSenses.weatherDrift(from: .nan, to: 1_013) == 0)

        // Falling pressure blows; rising lets it die away, the other way about.
        #expect(WorldSenses.wind(weatherDrift: falling) == 5)
        #expect(WorldSenses.wind(weatherDrift: rising) == -5)
        #expect(WorldSenses.wind(weatherDrift: 0) == 0)

        // A settled high is warm, a storm is cold, and neither is ever enough to freeze water or melt anything.
        #expect(WorldSenses.roomTemperature(weather: 1) == 28)
        #expect(WorldSenses.roomTemperature(weather: 0) == 20)
        #expect(WorldSenses.roomTemperature(weather: -1) == 12)
        #expect(WorldSenses.roomTemperature(weather: .nan) == 20)
        for weather in [-1.0, -0.5, 0, 0.5, 1.0] {
            let room = WorldSenses.roomTemperature(weather: weather)
            #expect(room > 0 && room < 100, "the weather set the room to \(room)°C")
        }
    }

    @Test("A day's walking makes the tide, and a few steps make none")
    func walkingMakesTheTide() {
        #expect(WorldSenses.tideStrength(steps: 0) == 0)
        #expect(WorldSenses.tideStrength(steps: 100) == 0, "standing up should not move the sea")
        #expect(WorldSenses.tideStrength(steps: -500) == 0)
        let stroll = WorldSenses.tideStrength(steps: 2_000)
        let day = WorldSenses.tideStrength(steps: 10_000)
        let marathon = WorldSenses.tideStrength(steps: 60_000)
        #expect(stroll > 0 && stroll < day)
        #expect(day == 60)
        #expect(marathon == day, "walking further than a full day did not stop at the strongest tide")
        // Every answer is one a tide will accept.
        for steps in [0, 150, 1_000, 5_000, 10_000, 100_000] {
            let strength = WorldSenses.tideStrength(steps: steps)
            let tide = PowderTide(side: .left, period: 3_600, strength: strength)
            #expect(tide.strength == strength, "a tide refused \(strength) from \(steps) steps")
        }
    }

    @Test("The sun is where the clock says, and blows the weather west")
    func theSun() {
        #expect(WorldSenses.sun(hour: 12) == 0)
        #expect(WorldSenses.sun(hour: 6) == -1)
        #expect(WorldSenses.sun(hour: 18) == 1)
        #expect(WorldSenses.sun(hour: 9) == -0.5)
        // Night is night.
        #expect(WorldSenses.sun(hour: 3) == nil)
        #expect(WorldSenses.sun(hour: 22) == nil)
        #expect(WorldSenses.sun(hour: 25) == nil)
        #expect(WorldSenses.sun(hour: .nan) == nil)

        #expect(WorldSenses.wind(sun: WorldSenses.sun(hour: 6)) == -3)
        #expect(WorldSenses.wind(sun: WorldSenses.sun(hour: 18)) == 3)
        #expect(WorldSenses.wind(sun: nil) == 0, "the wind blew at night")
    }

    @Test("A dark room makes a quieter picture, and never an invisible one")
    func theRoom() {
        #expect(WorldSenses.pictureBrightness(screen: 1) == 1)
        #expect(WorldSenses.pictureBrightness(screen: 0) == 0.34)
        #expect(WorldSenses.pictureBrightness(screen: .nan) == 1)
        // Whatever the room, the world can still be seen.
        for screen in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let brightness = WorldSenses.pictureBrightness(screen: screen)
            #expect(brightness >= 0.34 && brightness <= 1, "\(screen) gave \(brightness)")
        }
        #expect(WorldSenses.isDarkRoom(screen: 0.1))
        #expect(!WorldSenses.isDarkRoom(screen: 0.6))
        #expect(!WorldSenses.isDarkRoom(screen: .nan))
    }
}
