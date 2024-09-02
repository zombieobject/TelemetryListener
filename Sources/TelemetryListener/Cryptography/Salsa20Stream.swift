//
//  SalsaCipherStream.swift
//

import Foundation

//http://www.ecrypt.eu.org/stream/svn/viewcvs.cgi/ecrypt/trunk/submissions/salsa20/full/verified.test-vectors?logsort=rev&rev=210&view=markup
public class Salsa20Stream: InputStream {
    let blockSize = 64
    var inputBuffer: UnsafeMutablePointer<UInt8>
    var outputBuffer: UnsafeMutablePointer<UInt8>
    var bufferSize = 0
    var bufferOffset = 0
    var eofReached = false
    var inputStream: InputStream
    var cipher: Salsa20Cipher!

    public var hasBytesAvailable: Bool {
        return !eofReached
    }

    public init(withStream: InputStream, key: Data, iv vector: Data) throws {
        self.inputStream = withStream
        cipher = try Salsa20Cipher(withKey: key, iv: vector)
        inputBuffer = UnsafeMutablePointer.allocate(capacity: blockSize)
        outputBuffer = UnsafeMutablePointer.allocate(capacity: blockSize)
    }

    deinit {
        inputBuffer.deallocate()
        outputBuffer.deallocate()
    }

    public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        var remaining = len
        var writePtr = buffer

        while remaining > 0 {
            if bufferOffset >= bufferSize {
                if processInputData() == false {
                    return len - remaining
                }
            }

            let existsData = min(remaining, bufferSize - bufferOffset)
            writePtr.initialize(from: (inputBuffer+bufferOffset), count: existsData)

            bufferOffset += existsData
            writePtr += existsData
            remaining -= existsData
        }

        return len
    }

    func processInputData() -> Bool {
        if eofReached {
            return false
        }

        bufferOffset = 0
        bufferSize = 0
        var inputBytes = 0

        inputBytes = inputStream.read(inputBuffer, maxLength: blockSize)
        if inputBytes < blockSize {
            eofReached = true
        }
        cipher.xor(input: inputBuffer, output: outputBuffer, length: inputBytes)
        bufferSize += inputBytes
        return true
    }
}

public extension String {
    func salsa20Encrypted(withKey key: String, initializationVector vector: String) -> Data? {
        guard let strData = self.data(using: .utf8) else {
            return nil
        }

        return strData.salsa20Encrypted(withKey: key, initializationVector: vector)
    }
}

public extension Data {
    func salsa20Encrypted(withKey: String, initializationVector: String) -> Data? {
        guard let keyData = withKey.data(using: .utf8),
            let ivData = initializationVector.data(using: .utf8) else {
                return nil
        }

        let dataStream = DataInputStream(withData: self)
        do {
            let salsa20Stream = try Salsa20Stream(withStream: dataStream, key: keyData, iv: ivData)
            var resultData = Data(count: self.count)
            var readLength: Int?
            resultData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> Void in
                readLength = salsa20Stream.read(bytes, maxLength: self.count)
            }

            guard readLength == self.count else {
                return nil
            }

            return resultData
        } catch {
            return nil
        }
    }
}