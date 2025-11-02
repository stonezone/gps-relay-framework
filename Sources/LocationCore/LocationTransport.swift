import Foundation

public protocol LocationTransport {
    func open()
    func push(_ fix: LocationFix)
    func close()
}
