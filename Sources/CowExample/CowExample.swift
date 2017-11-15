internal class ArrayStorage<T> {
    init() {
        self.memory = nil
        self.capacity = 0
        self.count = 0
    }

    deinit {
        for i in 0..<count {
            remove(at: count - 1 - i)
        }
        reserveCapacity(0)
    }
    
    public private(set) var count: Int
    
    public subscript(index: Int) -> T {
        get {
            return memory![index]
        }
        set {
            memory![index] = newValue
        }
    }
    
    public func append(_ element: T) {
        if count == capacity {
            if capacity == 0 {
                reserveCapacity(4)
            } else {
                reserveCapacity(capacity * 2)
            }
        }
        
        (memory! + count).initialize(to: element)
        count += 1
    }
    
    public func remove(at index: Int) {
        (memory! + index).deinitialize()
        for i in index..<count {
            (memory! + i).moveInitialize(from: (memory! + i + 1), count: 1)
        }
        count -= 1
    }
    
    private func reserveCapacity(_ newCapacity: Int) {
        let newMemory: UnsafeMutablePointer<T>?
        if newCapacity > 0 {
            newMemory = UnsafeMutablePointer<T>.allocate(capacity: newCapacity)
        } else {
            newMemory = nil
        }
        
        let moveCount = min(count, newCapacity)
        let deinitCount = capacity - moveCount

        if let nmem = newMemory {
            if moveCount > 0 {
                nmem.moveInitialize(from: memory!, count: moveCount)
            }
        }
        if let mem = memory {
            if deinitCount > 0 {
                (mem + moveCount).deinitialize(count: capacity - moveCount)
            }
            mem.deallocate(capacity: capacity)
        }
        
        memory = newMemory
        capacity = newCapacity
    }
    
    private var memory: UnsafeMutablePointer<T>?
    private var capacity: Int
}

protocol A {
    subscript(index: Int) -> Int { get set }
}

//public struct CoWArray<T> {
//    public init()
//
//    public var count: Int { get }
//
//    public subscript(index: Int) -> T { get set }
//
//    public mutating func append(_ element: T)
//
//    public mutating func remove(at index: Int)
//}

func f() {
    var a = ArrayStorage<Int>()
    isKnownUniquelyReferenced(&<#T##object: T##T#>)
}
