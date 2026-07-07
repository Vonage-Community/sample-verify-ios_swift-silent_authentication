import VonageClientLibrary

protocol CellularRequestClientProtocol: Sendable {
    func startCellularGetRequest(
        params: VGCellularRequestParameters,
        debug: Bool
    ) async throws -> [String: Any]
}

extension VGCellularRequestClient: CellularRequestClientProtocol {}
