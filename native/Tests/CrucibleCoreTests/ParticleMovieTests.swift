@testable import CrucibleCore
import Foundation
import Testing

@Suite("The movie studio")
struct ParticleMovieTests {
    static let near = ParticleCamera(zoom: 4, panX: 100, panY: -40, orbitYaw: 170, orbitPitch: 10)
    static let far = ParticleCamera(zoom: 1, panX: 0, panY: 0, orbitYaw: -170, orbitPitch: 40)

    static func twoStops() -> ParticleMovie {
        ParticleMovie(stops: [
            .init(camera: near, travel: 9, hold: 1, speed: 1, caption: "  The start  "),
            .init(camera: far, travel: 4, hold: 2, speed: 0.25, caption: "Slow now"),
        ])
    }

    @Test("It runs for the holds and the journeys, and the first stop is cut to rather than travelled to")
    func duration() {
        #expect(Self.twoStops().duration == 1 + 4 + 2)
        #expect(!ParticleMovie(stops: [.init(camera: Self.near)]).canPlay)
        #expect(Self.twoStops().canPlay)
    }

    @Test("At the start it is at the first stop, saying its caption without the spaces round it")
    func startsAtTheFirstStop() throws {
        let moment = try #require(Self.twoStops().moment(at: 0.5))
        #expect(moment.camera == Self.near)
        #expect(moment.caption == "The start")
        #expect(!moment.isTravelling && moment.stop == 0)
        #expect(moment.speed == 1)
    }

    @Test("Captions fade in on arrival and out before leaving")
    func captionsFade() throws {
        let movie = Self.twoStops()
        let arriving = try #require(movie.moment(at: 0))
        #expect(arriving.captionOpacity == 0)
        let settled = try #require(movie.moment(at: 0.5))
        #expect(settled.captionOpacity == 1)
        let leaving = try #require(movie.moment(at: 0.99))
        #expect(leaving.captionOpacity < 0.1)
    }

    @Test("On the way it says nothing, turns the short way round, and eases the world's speed down")
    func travelling() throws {
        let movie = Self.twoStops()
        let halfway = try #require(movie.moment(at: 1 + 2))
        #expect(halfway.isTravelling && halfway.stop == 1)
        #expect(halfway.caption == nil)
        // From 170 to -170 is twenty degrees through 180, not three hundred and forty back through nought.
        #expect(abs(abs(halfway.camera.orbitYaw) - 180) < 1e-6, "went \(halfway.camera.orbitYaw)")
        #expect(abs(halfway.camera.orbitPitch - 25) < 1e-6)
        // Zoom halfway between four and one by doubling, which is two.
        #expect(abs(halfway.camera.zoom - 2) < 1e-6)
        #expect(abs(halfway.speed - 0.625) < 1e-9)
    }

    @Test("It sets off gently and arrives gently")
    func eases() throws {
        let movie = Self.twoStops()
        let early = try #require(movie.moment(at: 1 + 0.4)).camera.panX
        let middle = try #require(movie.moment(at: 1 + 2)).camera.panX
        // A tenth of the way in time covers far less than a tenth of the way.
        #expect(100 - early < 10 * 0.5, "moved \(100 - early)")
        #expect(abs(middle - 50) < 1e-6)
        #expect(ParticleMovie.ease(0) == 0 && ParticleMovie.ease(1) == 1 && ParticleMovie.ease(0.5) == 0.5)
    }

    @Test("Once over it says so and stays at the last stop")
    func finishes() throws {
        let moment = try #require(Self.twoStops().moment(at: 99))
        #expect(moment.isFinished)
        #expect(moment.camera == Self.far)
        #expect(moment.caption == nil)
        #expect(ParticleMovie().moment(at: 0) == nil)
    }

    @Test("A stop keeps the spin's angle, not the spin, and takes room made by zooming out as the whole world")
    func stopsAreStill() {
        var spinning = ParticleCamera(zoom: 0.5, orbitYaw: 10)
        spinning.autoOrbit = true
        spinning.autoOrbitAngle = 30
        let stop = ParticleMovie.Stop(camera: spinning)
        #expect(!stop.camera.autoOrbit && stop.camera.autoOrbitAngle == 0)
        #expect(abs(stop.camera.orbitYaw - 40) < 1e-9)
        #expect(stop.camera.zoom == 1)
        #expect(stop.camera.worldScale == 1, "a movie must never resize the world on the way")
    }

    @Test("Every setting is held to what makes sense, and a caption to a sentence")
    func limits() {
        let stop = ParticleMovie.Stop(
            camera: .identity, travel: -4, hold: .infinity, speed: 50,
            caption: String(repeating: "a", count: 500)
        )
        #expect(stop.travel == ParticleMovie.Stop.travelRange.lowerBound)
        #expect(stop.hold == 2)
        #expect(stop.speed == ParticleMovie.Stop.speedRange.upperBound)
        #expect(stop.caption.count == ParticleMovie.Stop.longestCaption)
        var movie = ParticleMovie()
        for _ in 0 ..< 20 { movie.add(.identity) }
        #expect(movie.stops.count == ParticleMovie.mostStops)
    }

    @Test("Editing moves, changes and removes stops, and ignores stops that are not there")
    func editing() {
        var movie = Self.twoStops()
        movie.moveEarlier(1)
        #expect(movie.stops[0].caption == "Slow now")
        movie.update(0, speed: 0.5, caption: "Changed")
        #expect(movie.stops[0].speed == 0.5 && movie.stops[0].caption == "Changed")
        movie.update(7, speed: 0.5)
        movie.remove(at: 7)
        movie.moveEarlier(0)
        movie.remove(at: 0)
        #expect(movie.stops.count == 1)
    }

    @Test("It survives being saved with a world, and a file with half of it missing still reads")
    func saving() throws {
        let movie = Self.twoStops()
        let data = try JSONEncoder().encode(movie)
        #expect(try JSONDecoder().decode(ParticleMovie.self, from: data) == movie)
        let sparse = Data(#"{"stops":[{"caption":"only this"},{"travel":1e9}]}"#.utf8)
        let read = try JSONDecoder().decode(ParticleMovie.self, from: sparse)
        #expect(read.stops.count == 2)
        #expect(read.stops[0].caption == "only this" && read.stops[0].hold == 2)
        #expect(read.stops[1].travel == ParticleMovie.Stop.travelRange.upperBound)
        #expect(try JSONDecoder().decode(ParticleMovie.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test("Scrubbing the whole movie never produces a camera that is not a camera")
    func everyMomentIsSane() throws {
        let movie = Self.twoStops()
        var time = 0.0
        while time < movie.duration + 1 {
            let moment = try #require(movie.moment(at: time))
            let camera = moment.camera
            for value in [camera.zoom, camera.panX, camera.panY, camera.orbitYaw, camera.orbitPitch, moment.speed] {
                #expect(value.isFinite)
            }
            #expect(camera.zoom >= 1 && camera.zoom <= 4)
            #expect(moment.captionOpacity >= 0 && moment.captionOpacity <= 1)
            time += 0.05
        }
    }
}
