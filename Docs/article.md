Swift の Array や Dictionary は Copy on Write になっていてとても使いやすいです。この記事では、そのような Copy on Write の実装方法を解説します。

# CoW の動作

Copy on Write はよく CoW と略されるので以後そのように呼びます。さて、 CoW はその名の通り、書き込みが生じる時にコピーをするものです。まずはその動作について説明します。

以下のコードを見てください。

```swift
var a = [1, 2, 3]
var b = a
```

変数 `a` に `[1, 2, 3]` を代入した後、 `b` にコピーしています。変数 `a` の配列は 3 つの値が入ったデータ領域を持っていますが、 `a` が `b` にコピーされたときには、そのデータ領域はコピーされません。その代わりに、 `b` は `a` の持っているデータ領域を共有します。だから、 `a` の配列の要素がどれだけ多くても、このコピーは高速で消費メモリもとても小さいです。

ただし、このままデータ領域が共有されているだけであれば `a` に変更を加えたら、 `b` の値も変化してしまいます。

```swift
a.append(4) // a に値 4 を追加する。
print(a) // "1, 2, 3, 4" が出力される。
print(b) // "1, 2, 3, 4" が出力されてしまうでしょうか？
```

実際に Swift を使ってみれば、 `b` の値はちゃんと `[1, 2, 3]` のままであることが確認できます。この動作は `append` を呼び出した時にデータ領域のコピーが行われることで実現されています。つまり `append` を呼び出した時点で `a` と `b` のデータ領域の共有が解除され、それぞれが固有のデータ領域を持った状態に変化します。 `append` は `a` に対する変更操作ですから、変更操作 (=Write) のタイミングでデータ領域のコピー (Copy) が行われています。これが、 Copy on Write の動作です。

さてこの時点で、 `a` は `[1, 2, 3, 4]` が入ったデータ領域、 `b` は `[1, 2, 3]` が入ったデータ領域を保持しています。ここで、さらに `a` に値を追加する事を考えてみます。

```swift
a.append(5)
```

もし、 `append` メソッドを呼び出すたびにデータ領域をコピーしていたら、この `append` の呼び出し時にも、 `[1, 2, 3, 4]` の入ったデータ領域をコピーしてから、その後で 5 を追加する事になってしまいますが、そのコピーは不要です。現在のデータ領域に 5 を追加するだけで良いからです。実際、この場合はコピーは行われません。

つまり、変更操作のタイミングならいつでもデータ領域のコピーを行うわけではなく、そこには更に条件があります。すなわち、変更操作が生じたとき、データ領域が他のオブジェクトと共有されているならば、データ領域のコピーを行う、というのがより正確な CoW の動作になります。

# CoW の設計

この章では、 CoW をもった配列を自作するためにその設計を示します。まず、配列それ自体の型を用意します。これは値型にします。名前は `CoWArray` とします。インターフェースを以下に示します。

```swift
public struct CoWArray<T> {
    public init()
    public var count: Int { get }
    public subscript(index: Int) -> T { get set }
    public mutating func append(_ element: T)
    public mutating func remove(at index: Int)
}
```

機能は要素数の取得とサブスクリプトでのアクセス、要素の追加と削除を用意します。サブスクリプトアクセスのセッターと、要素の追加、削除は `mutating` メソッドになります。

次に、データ領域を表す型を用意します。これは他の配列と共有する必要があるので参照型にします。名前は `CowArrayStorage` とします。インターフェースを以下に示します。

```swift
internal class CoWArrayStorage<T> {
	public init()
	public init(copy: CoWArrayStorage<T>)
	public var count: Int { get }
	public subscript(index: Int) -> T { get set }
	public func append(_ element: T)
	public func remove(at index: Int)
}
```

定義を `CoWArray` と見比べると、 `init(copy:)` が追加されている以外は同じになっています。これがポイントです。

`CoWArray` は内部でプロパティとして `CoWArrayStorage` を保持します。そして、全てのメソッドはそのストレージの同名メソッドを呼び出すだけにします。ただし、変更が発生するメソッド、つまり `mutating` なメソッドの場合は、ストレージのメソッドを呼び出す前に、ストレージが他のオブジェクトから共有されているかチェックして、もし共有されている場合はコピーをする処理をはさみます。これが CoW を実現する肝になります。

ストレージが共有されているかどうかは、 Swift 標準ライブラリの [`isKnownUniquelyReferenced`](https://developer.apple.com/documentation/swift/2430721-isknownuniquelyreferenced) 関数を使います。この関数は、引数で与えた参照型の値が、ユニークであれば、つまり共有されていなければ `true` を返します。ユニークでなければ、つまり共有されていれば `false` を返します。内部的には、参照型のオブジェクトが内部に持っている参照カウンタの値を調べて、それが 1 か 2以上かどうかで判定しています。

設計は以上です。

# CoW の実装

この章では実装を行います。まず、配列の機能本体を提供する `CoWArrayStorage` の実装を示し、次に配列自体を提供する `CoWArray` の実装を示します。前者の詳細は CoW の実現とは特に関係が無いので読み飛ばしても良いです。後者は CoW の重要なポイントになります。

この手の配列の実装では、 `replaceSubrange` を実装すれば、 `append`, `insert`, `remove`, `subscript set` はいずれも `replaceSubrange` の呼び出しで済ませられますが、今回はシンプルにするために `append` と `remove` の直接の実装だけを行います。

## データ領域の実装

### データ構造

 `CoWArrayStorage` はメモリ領域を示すポインタ `memory` と、そのメモリ領域の大きさを示す `capacity` 、配列に入っている要素の個数を表す `count` をプロパティとして持ちます。 `capacity` と `count` の 2 つを用意することで、配列の要素数よりも余分にメモリ領域を持っておく事ができます。そうすると、 `append` する時にメモリ領域の拡張を省略できる場合があります。ここまでの実装を示します。

```swift
internal class CoWArrayStorage<T> {
    public init() {
        self.memory = nil
        self.capacity = 0
        self.count = 0
    }

    private var memory: UnsafeMutablePointer<T>?
    private var capacity: Int
    private var count: Int
}
```

なお、 `capacity` が 0 のときは、 `memory` は `nil` にするという規約にします。 `deinit` ではデータ領域の解放が必要ですが、それは後で書きます。

### subscript

`subscript` と `count` については素直に実装します。

```swift
    public private(set) var count: Int
    
    public subscript(index: Int) -> T {
        get {
            return memory![index]
        }
        set {
            memory![index] = newValue
        }
    }
```

`subscript` の範囲チェックは省略しました。メモリ安全にしたければチェックしてください。

### reserveCapacity

メモリ領域のリサイズを行う関数、 `reserveCapacity` を実装します。

この関数は、はじめに新しい領域を確保し、そこに古い領域のデータをコピーして、さいごに古い領域を解放します。この時に注意しなければならないのが、ポインタの 3 つの状態です。ポインタには、 未確保、未初期化、初期化済の 3種類の状態があります。今回のポインタは連続領域なので、まず領域を指しているかどうかで未確保か確保済みの 2 つがあり、確保済みの場合において、領域の 1 要素ごとに、未初期化か初期化済があります。また、新しいメモリ領域は、大きくなる場合と小さくなる場合があり、小さくなる場合には 0 になる場合もあります。このポインタの状態については、過去に [解説記事](https://qiita.com/omochimetaru/items/c95e0d36ae7f1b1a9052#ポインタの3つの状態) を書いたので参考にしてください。

まず、大きくなる場合は、古いの領域の要素を全て新しい領域に移す事ができます。これは、新しい領域に対しては 未初期化領域を初期化する操作なので、 `initialize` 操作になります。古い領域に対しては、初期化済み領域を未初期化に戻す操作なので `deinitialize` 操作になります。2 つの領域があって、片方を `deinitialize` しながら別の領域に書き込む操作は `move` 操作になります。なので `moveInitialize` を使うと一発で記述できます。

小さくなる場合には、古い領域の要素のうち、新しい領域に入る分と、入り切らない分が出てきます。入りきる分については同様に `moveInitialize` で移動させて、入り切らない分については破棄します。破棄するためには `deinitialize` が使えます。この、前半を `moveInitialize` 、 後半を `deinitialize` するロジックは、その境界となる要素番号を使って書いてやれば、大きくなる場合とひとまとめに書くことができます。

0 になる場合については、新しい領域のポインタは `nil` にしておく以外は小さくなる場合と同じです。

最後に 古い領域を `deallocate` で解放して、 `memory` プロパティと `capacity` プロパティを更新して完了です。

なお、 `count` プロパティについてはこの関数では関与しない規約とします。

以上の方針で実装したコードが下記になります。

```swift
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
```

### deinit での破棄と解放

メモリ確保処理を実装したので、ここで忘れずに `deinit` でのメモリ解放も記述しておきます。データ領域は先頭から要素数分は初期化済みなので、これの破棄も行います。

```swift
    deinit {
        memory?.deinitialize(count: count)
        reserveCapacity(0)
    }
```

### append

`append` では、最初にメモリ領域が足りているかチェックします。足りていない場合は、先程の `reserveCapacity` を使ってメモリ確保をします。ここで領域の拡大は要素 1 つ分にせず、一気に領域を 2 倍に広げるようにすると効率的です。連続で `append` が呼び出される場合に、メモリの再確保の頻度が減らせるからです。しかし、領域の大きさが 0 の場合には 2 倍にしても 0 のままなので、特別に初期値を設定しておきます。メモリ領域の準備ができたら、末尾に要素を追加します。ここもやはり、未初期化領域を初期化する操作なので、 `initialize` 操作をします。最後に要素数を 1 増やします。以下にコードを示します。

```swift
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
```

### remove

`remove` では、指定されたインデックスの要素を削除した後、後続の要素を 1 つずつ前にずらします。まず、削除する操作は `deinitialize` です。これによって削除された場所は未初期化になります。そして、 1 つ後ろの要素を、削除された要素のあった場所に移動させるわけですが、これは `reserveCapacity` のときと同様、移動元が初期化済で、移動先が未初期化なので、 `moveInitialize` で書けます。最後に要素数を 1 減らします。

```swift
    public func remove(at index: Int) {
        (memory! + index).deinitialize()
        for i in index..<count {
            (memory! + i).moveInitialize(from: (memory! + i + 1), count: 1)
        }
        count -= 1
    }
```

### コピー init

最後に、コピー用の `init` を作ります。コピーする要素数でメモリ確保して、確保した未初期化領域をまとめて `initialize` します。

```swift
    public init(copy: CoWArrayStorage<T>) {
        self.count = copy.count
        self.capacity = count
        self.memory = UnsafeMutablePointer<T>.allocate(capacity: count)
        
        memory?.initialize(from: copy.memory!, count: count)
    }
```

### まとめ

以上で `CoWArrayStorage` が実装できました。

## CoW 型の実装

いよいよ CoW 型の実装をします。まず、データ構造ですが、ストレージオブジェクトを保持するだけです。

```swift
public struct CoWArray<T> {
    public init() {
        self.storage = .init()
    }

    private var storage: CoWArrayStorage<T>
}
```

次に、 CoW の肝となる、共有されていればストレージをコピーするメソッドを作ります。共有されているかどうかは `isKnownUniquelyReference` でチェックして、コピーは先程作ったコピー用の `init` を使います。

```swift
    private mutating func copyStorageIfShared() {
        if isKnownUniquelyReferenced(&storage) {
            return
        }
        
        storage = .init(copy: storage)
    }
```

あとは、全てのメソッドを素通ししつつ、 `mutating` なものについては事前に `copyStorageIfShared` を呼び出すだけです。

```swift
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
```

これで CoW な配列が完成しました。

# ソース

[完成したソースはこちらにアップしてあります。](https://github.com/omochi/swift-cow-example)


