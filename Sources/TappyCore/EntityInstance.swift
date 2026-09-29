import Foundation

/// One entity currently on screen.
public struct EntityInstance: Identifiable, Equatable {
    public let id = UUID()
    public let definition: EntityDefinition
    /// Position in normalized coordinates (0...1), resolved against the view size.
    public let position: CGPoint
    public let size: CGFloat
    public let baseRotation: Double
    /// Stable slot (0...1) in the parade's marching loop. Assigned at spawn
    /// and never changes, so other entities joining or leaving the parade
    /// do not shift this one's position.
    public let paradePhase: Double

    public init(definition: EntityDefinition, position: CGPoint, paradePhase: Double = 0,
                sizeBoost: CGFloat = 1) {
        self.definition = definition
        self.position = position
        self.paradePhase = paradePhase
        self.size = .random(in: 90...150) * definition.sizeScale * sizeBoost
        self.baseRotation = .random(in: -12...12)
    }
}
