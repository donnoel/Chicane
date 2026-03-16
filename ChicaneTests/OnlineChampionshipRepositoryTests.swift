import XCTest
@testable import Chicane

final class OnlineChampionshipRepositoryTests: XCTestCase {
    func testMotoGPWorldStandingsPayloadDecodesWrappedClassificationShape() throws {
        let json = """
        {
          "classification": {
            "rider": [
              {
                "position": 1,
                "points": 32,
                "team_name": "Red Bull KTM Factory Racing",
                "rider": {
                  "full_name": "Pedro Acosta"
                }
              },
              {
                "position": "2",
                "points": "29",
                "team_name": "Aprilia Racing",
                "rider": {
                  "name": "Marco",
                  "surname": "Bezzecchi"
                }
              }
            ]
          }
        }
        """

        let payload = try JSONDecoder().decode(MotoGPWorldStandingsPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.classification.count, 2)
        XCTAssertEqual(payload.classification[0].position, 1)
        XCTAssertEqual(payload.classification[0].rider?.fullName, "Pedro Acosta")
        XCTAssertEqual(payload.classification[1].position, 2)
        XCTAssertEqual(payload.classification[1].points, 29)
        XCTAssertEqual(payload.classification[1].rider?.surname, "Bezzecchi")
    }

    func testMotoGPWorldStandingsPayloadDecodesDirectArrayShape() throws {
        let json = """
        {
          "classification": [
            {
              "position": 1,
              "points": 40,
              "team_name": "Ducati Lenovo Team",
              "rider": {
                "full_name": "Francesco Bagnaia"
              }
            }
          ]
        }
        """

        let payload = try JSONDecoder().decode(MotoGPWorldStandingsPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.classification.count, 1)
        XCTAssertEqual(payload.classification[0].position, 1)
        XCTAssertEqual(payload.classification[0].points, 40)
        XCTAssertEqual(payload.classification[0].rider?.fullName, "Francesco Bagnaia")
    }
}
