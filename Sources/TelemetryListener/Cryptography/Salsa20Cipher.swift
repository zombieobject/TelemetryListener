//
//  Salsa20Cipher.swift
//
//
// https://botan.randombit.net/doxygen/salsa20_8cpp_source.html Crypto and TLS for C++11
//https://courses.csail.mit.edu/6.857/2016/files/salsa20.py
import Foundation

public protocol RandomGenerator {
    func xor(input inBuffer: UnsafePointer<UInt8>, output outBuffer: UnsafeMutablePointer<UInt8>, length: Int)
    func get<ReturnType: FixedWidthInteger>() -> ReturnType
    func reset()
}

public class Salsa20Cipher {
    enum Salsa20CryptorError: Error {
        case invalidKeySize
        case invalidIVSize
    }

    public enum Rounds: Int {
        case salsa2020 = 10
        case salsa2012 = 6
        case salsa2008 = 4
    }

    public static let SIGMA: [UInt32] = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574]
    public static let TAU: [UInt32] = [0x61707865, 0x3120646e, 0x79622d36, 0x6b206574]
    public let rounds: Rounds
    var index = 0
    var state: UnsafeMutablePointer<UInt32>
    var keyStream: UnsafeMutablePointer<UInt8>

    public init(withKey: Data, iv vector: Data, rounds: Rounds = .salsa2020) throws {
        self.rounds = rounds

        guard withKey.count == 16 || withKey.count == 32 else {
            throw Salsa20CryptorError.invalidKeySize
        }

        keyStream = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        state = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        state.initialize(repeating: 0, count: 16)
        withKey.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Void in
            if withKey.count == 32 {
                expand32BytesKey(bytes)
            } else if withKey.count == 16 {
                expand16BytesKey(bytes)
            }
        }

        guard vector.count == 8 else {
            throw Salsa20CryptorError.invalidIVSize
        }

        vector.withUnsafeBytes { bytes -> Void in
            set8BytesIV(bytes)
        }
    }

    deinit {
        keyStream.deallocate()
        state.deallocate()
    }

    func expand32BytesKey(_ key: UnsafePointer<UInt8>) {
        state[00] = Salsa20Cipher.SIGMA[00]
        state[01] = Salsa20Cipher.read(key+00)
        state[02] = Salsa20Cipher.read(key+04)
        state[03] = Salsa20Cipher.read(key+08)
        state[04] = Salsa20Cipher.read(key+12)
        state[05] = Salsa20Cipher.SIGMA[01]
        state[10] = Salsa20Cipher.SIGMA[02]
        state[11] = Salsa20Cipher.read(key+16)
        state[12] = Salsa20Cipher.read(key+20)
        state[13] = Salsa20Cipher.read(key+24)
        state[14] = Salsa20Cipher.read(key+28)
        state[15] = Salsa20Cipher.SIGMA[03]
    }

    func expand16BytesKey(_ key: UnsafePointer<UInt8>) {
        state[00] = Salsa20Cipher.TAU[00]
        state[01] = Salsa20Cipher.read(key+00, count: 2)
        state[02] = Salsa20Cipher.read(key+02, count: 2)
        state[03] = Salsa20Cipher.read(key+04, count: 2)
        state[04] = Salsa20Cipher.read(key+06, count: 2)
        state[05] = Salsa20Cipher.TAU[01]
        state[10] = Salsa20Cipher.TAU[02]
        state[11] = Salsa20Cipher.read(key+08, count: 2)
        state[12] = Salsa20Cipher.read(key+10, count: 2)
        state[13] = Salsa20Cipher.read(key+12, count: 2)
        state[14] = Salsa20Cipher.read(key+14, count: 2)
        state[15] = Salsa20Cipher.TAU[03]
    }

    func set8BytesIV(_ vector: UnsafePointer<UInt8>) {
        state[06] = Salsa20Cipher.read(vector+00)
        state[07] = Salsa20Cipher.read(vector+04)
        state[08] = 0
        state[09] = 0
    }

    func salsa20() {
        let xstate = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        xstate.initialize(from: state, count: 16)

        for _ in 0..<rounds.rawValue {
            Salsa20Cipher.doubleRound(xstate)
        }

        for i in 0..<16 {
            xstate[i] = xstate[i]&+state[i]
            Salsa20Cipher.write(xstate+i, to: (keyStream+i*4))
        }

        incrementCounter()

        xstate.deallocate()
    }

    func getByte() -> UInt8 {
        if index == 0 {
            salsa20()
        }

        let value = (keyStream+index).pointee
        index = (index + 1) & 0x3F

        return value
    }

    func incrementCounter() {
        state[8] = state[8] &+ 1
        if state[8] == 0 {
            state[9] = state[9] &+ 1
        }
    }
}

extension Salsa20Cipher {
    static func salsa20Hash(input inBuffer: UnsafePointer<UInt8>,
                            output outBuffer: UnsafeMutablePointer<UInt8>,
                            rounds: Rounds = Rounds.salsa2020) {
        let in32Buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        for i in 0..<16 {
            in32Buffer[i] = read(inBuffer+i*4)
        }

        salsa20Hash(input: in32Buffer, output: outBuffer)
    }

    static func salsa20Hash(input inBuffer: UnsafePointer<UInt32>,
                            output outBuffer: UnsafeMutablePointer<UInt8>,
                            rounds: Rounds = Rounds.salsa2020) {
        let xstate = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        xstate.initialize(from: inBuffer, count: 16)

        for _ in 0..<rounds.rawValue {
            doubleRound(xstate)
        }

        for i in 0..<16 {
            xstate[i] = xstate[i]&+inBuffer[i]
            write(xstate+i, to: (outBuffer+4*i))
        }

        xstate.deallocate()
    }

    static func write(_ uint32Ptr: UnsafeMutablePointer<UInt32>, to buffer: UnsafeMutablePointer<UInt8>) {
        let count = MemoryLayout<UInt32>.size
        uint32Ptr.withMemoryRebound(to: UInt8.self, capacity: count) { uint8Ptr -> Void in
            buffer[0] = uint8Ptr[0]
            buffer[1] = uint8Ptr[1]
            buffer[2] = uint8Ptr[2]
            buffer[3] = uint8Ptr[3]
        }
    }

    static func write(_ uint32Ptr: UnsafeMutablePointer<UInt32>, to buffer: UnsafeMutablePointer<UInt32>) {
        buffer.pointee = uint32Ptr.pointee
    }

    static func read(_ uint8Ptr: UnsafePointer<UInt8>, count: Int = 4) -> UInt32 {
        var uint32: UInt32 = 0
        withUnsafeMutableBytes(of: &uint32) { uint32Ptr -> Void in
            for i in 0..<count {
                uint32Ptr[i] = uint8Ptr[i]
            }
        }
        return uint32
    }

    static func xor(keyBuffer: UnsafePointer<UInt8>,
                    input inBuffer: UnsafePointer<UInt8>,
                    output outBuffer: UnsafeMutablePointer<UInt8>) {
        for i in 0..<64 {
            outBuffer[i] = inBuffer[i]^keyBuffer[i]
        }
    }

    static func quarterRound(ptr0: UnsafeMutablePointer<UInt32>,
                             ptr1: UnsafeMutablePointer<UInt32>,
                             ptr2: UnsafeMutablePointer<UInt32>,
                             ptr3: UnsafeMutablePointer<UInt32>) {
        ptr1.pointee ^= rotl(value: ptr0.pointee&+ptr3.pointee, shift: 07)
        ptr2.pointee ^= rotl(value: ptr1.pointee&+ptr0.pointee, shift: 09)
        ptr3.pointee ^= rotl(value: ptr2.pointee&+ptr1.pointee, shift: 13)
        ptr0.pointee ^= rotl(value: ptr3.pointee&+ptr2.pointee, shift: 18)
    }

    static func rowRound(_ ptr: UnsafeMutablePointer<UInt32>) {
        quarterRound(ptr0: ptr+00, ptr1: ptr+01, ptr2: ptr+02, ptr3: ptr+03)
        quarterRound(ptr0: ptr+05, ptr1: ptr+06, ptr2: ptr+07, ptr3: ptr+04)
        quarterRound(ptr0: ptr+10, ptr1: ptr+11, ptr2: ptr+08, ptr3: ptr+09)
        quarterRound(ptr0: ptr+15, ptr1: ptr+12, ptr2: ptr+13, ptr3: ptr+14)
    }

    static func columnRound(_ ptr: UnsafeMutablePointer<UInt32>) {
        quarterRound(ptr0: ptr+00, ptr1: ptr+04, ptr2: ptr+08, ptr3: ptr+12)
        quarterRound(ptr0: ptr+05, ptr1: ptr+09, ptr2: ptr+13, ptr3: ptr+01)
        quarterRound(ptr0: ptr+10, ptr1: ptr+14, ptr2: ptr+02, ptr3: ptr+06)
        quarterRound(ptr0: ptr+15, ptr1: ptr+03, ptr2: ptr+07, ptr3: ptr+11)
    }

    static func doubleRound(_ ptr: UnsafeMutablePointer<UInt32>) {
        columnRound(ptr)
        rowRound(ptr)
    }

    static func rotl(value: UInt32, shift: UInt32) -> UInt32 {
        return (value<<shift)|(value>>(32-shift))
    }

    static func printState(_ bytes: UnsafeMutablePointer<UInt32>) {
        print("state")
        for i in 0..<4 {
            let col0 = Data(bytes: (bytes+i*4), count: 4)
            let col1 = Data(bytes: (bytes+i*4+1), count: 4)
            let col2 = Data(bytes: (bytes+i*4+2), count: 4)
            let col3 = Data(bytes: (bytes+i*4+3), count: 4)
            print("\(col0.hexString) \(col1.hexString) \(col2.hexString) \(col3.hexString)")
        }
    }

    static func printKeyStream(_ bytes: UnsafeMutablePointer<UInt8>) {
        print("key stream")
        for i in 0..<4 {
            let col0 = Data(bytes: (bytes+i*4), count: 4)
            let col1 = Data(bytes: (bytes+i*4+4), count: 4)
            let col2 = Data(bytes: (bytes+i*4+8), count: 4)
            let col3 = Data(bytes: (bytes+i*4+12), count: 4)
            print("\(col0.hexString) \(col1.hexString) \(col2.hexString) \(col3.hexString)")
        }
    }

    static func printQuarterRound(_ buffer: UnsafeMutablePointer<UInt32>) {
        print("quarter round")
        let col0 = Data(bytes: (buffer+0), count: 4)
        let col1 = Data(bytes: (buffer+1), count: 4)
        let col2 = Data(bytes: (buffer+2), count: 4)
        let col3 = Data(bytes: (buffer+3), count: 4)
        print("\(col0.hexString) \(col1.hexString) \(col2.hexString) \(col3.hexString)")
    }

    static func printQuarterAdresses(_ buffer: UnsafeMutablePointer<UInt32>) {
        print("quarter adresses")
        print("buffer+0: \(buffer+0)")
        print("buffer+1: \(buffer+1)")
        print("buffer+2: \(buffer+2)")
        print("buffer+3: \(buffer+3)")
    }

    static func printUInt32(_ uint32Ptr: UnsafePointer<UInt32>) {
        uint32Ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { bytes -> Void in
            let byte0 = Data(bytes: (bytes+0), count: 1)
            let byte1 = Data(bytes: (bytes+1), count: 1)
            let byte2 = Data(bytes: (bytes+2), count: 1)
            let byte3 = Data(bytes: (bytes+3), count: 1)
            print("\(byte0.hexString) \(byte1.hexString) \(byte2.hexString) \(byte3.hexString)")
        }
    }

    static func printUInt16(_ uint16Ptr: UnsafePointer<UInt16>) {
        uint16Ptr.withMemoryRebound(to: UInt8.self, capacity: 2) { bytes -> Void in
            let byte0 = Data(bytes: (bytes+0), count: 1)
            let byte1 = Data(bytes: (bytes+1), count: 1)
            print("\(byte0.hexString) \(byte1.hexString)")
        }
    }
}

extension Salsa20Cipher: RandomGenerator {
    public func xor(input inBuffer: UnsafePointer<UInt8>, output outBuffer: UnsafeMutablePointer<UInt8>, length: Int) {
        for i in 0..<length {
            outBuffer[i] = inBuffer[i]^getByte()
        }
    }

    public func get<ReturnType: FixedWidthInteger>() -> ReturnType {
        var result: ReturnType = 0
        withUnsafeMutablePointer(to: &result) { ptr -> Void in
            let count = MemoryLayout<ReturnType>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count) { byte -> Void in
                for i in 0..<count {
                    (byte+i).pointee = getByte()
                }
            }
        }

        return result
    }

    public func reset() {
        state[08] = 0
        state[09] = 0
        index = 0
    }
}