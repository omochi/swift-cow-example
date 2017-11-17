internal class CoWArrayStorage<T> {
    public init() {
        self.memory = nil
        self.capacity = 0
        self.count = 0
    }
    
    public init(copy: CoWArrayStorage<T>) {
        self.count = copy.count
        self.capacity = count
        self.memory = UnsafeMutablePointer<T>.allocate(capacity: count)
        
        memory?.initialize(from: copy.memory!, count: count)
    }

    deinit {
        memory?.deinitialize(count: count)
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
        let moveNum = count - index - 1
        if moveNum > 0 {
            (memory! + index).moveInitialize(from: (memory! + index + 1), count: moveNum)
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

public struct CoWArray<T> {
    public init() {
        self.storage = .init()
    }

    public var count: Int {
        return storage.count
    }

    public subscript(index: Int) -> T {
        get {
            return storage[index]
        }
        set {
            copyStorageIfShared()
            storage[index] = newValue
        }
    }

    public mutating func append(_ element: T) {
        copyStorageIfShared()
        storage.append(element)
    }

    public mutating func remove(at index: Int) {
        copyStorageIfShared()
        storage.remove(at: index)
    }
    
    private mutating func copyStorageIfShared() {
        if isKnownUniquelyReferenced(&storage) {
            return
        }
        
        storage = .init(copy: storage)
    }
    
    private var storage: CoWArrayStorage<T>
}


