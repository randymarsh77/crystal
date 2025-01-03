internal struct SendableShim<T>: @unchecked Sendable {
	let value: T
	public init(_ value: T) {
		self.value = value
	}
}
