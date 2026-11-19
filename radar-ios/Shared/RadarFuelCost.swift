import Foundation

enum RadarFuelCost {
    static func perKilometer(pricePerLiter: Double, kilometersPerLiter: Double) -> Double? {
        guard pricePerLiter.isFinite, pricePerLiter > 0,
              kilometersPerLiter.isFinite, kilometersPerLiter > 0 else { return nil }
        let cost = pricePerLiter / kilometersPerLiter
        return cost.isFinite && cost > 0 ? cost : nil
    }
}
