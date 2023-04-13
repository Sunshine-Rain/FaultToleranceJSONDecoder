//
//  FaultToleranceJsonDecoder.swift
//  jesonDecoder_test
//
//  Created by quan on 2023/3/29.
//

import Foundation
import SwiftyJSON

fileprivate struct _CUSJSONKey : CodingKey {
    static let `super`: _CUSJSONKey = _CUSJSONKey(stringValue: "super")
    
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
    
    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}

fileprivate protocol _CUSJSONStringDictionaryDecodableMarker {
    static var elementType: Decodable.Type { get }
}

extension Dictionary: _CUSJSONStringDictionaryDecodableMarker where Key == String, Value: Decodable {
    static var elementType: Decodable.Type { return Value.self }
}

extension Decodable {
    fileprivate static func createByDirectlyUnwrapping(from decoder: FaultToleranceJSONDecoderImpl) throws -> Self {
        if Self.self == URL.self
            || Self.self == Date.self
            || Self.self == Data.self
            || Self.self == Decimal.self
            || Self.self is _CUSJSONStringDictionaryDecodableMarker.Type
        {
            return try decoder.unwrap(as: Self.self)
        }

        return try Self.init(from: decoder)
    }
}

fileprivate func _cusConvertFromSnakeCase(_ stringKey: String) -> String {
    guard !stringKey.isEmpty else { return stringKey }

    // Find the first non-underscore character
    guard let firstNonUnderscore = stringKey.firstIndex(where: { $0 != "_" }) else {
        // Reached the end without finding an _
        return stringKey
    }

    // Find the last non-underscore character
    var lastNonUnderscore = stringKey.index(before: stringKey.endIndex)
    while lastNonUnderscore > firstNonUnderscore && stringKey[lastNonUnderscore] == "_" {
        stringKey.formIndex(before: &lastNonUnderscore)
    }

    let keyRange = firstNonUnderscore...lastNonUnderscore
    let leadingUnderscoreRange = stringKey.startIndex..<firstNonUnderscore
    let trailingUnderscoreRange = stringKey.index(after: lastNonUnderscore)..<stringKey.endIndex

    let components = stringKey[keyRange].split(separator: "_")
    let joinedString: String
    if components.count == 1 {
        // No underscores in key, leave the word as is - maybe already camel cased
        joinedString = String(stringKey[keyRange])
    } else {
        joinedString = ([components[0].lowercased()] + components[1...].map { $0.capitalized }).joined()
    }

    // Do a cheap isEmpty check before creating and appending potentially empty strings
    let result: String
    if (leadingUnderscoreRange.isEmpty && trailingUnderscoreRange.isEmpty) {
        result = joinedString
    } else if (!leadingUnderscoreRange.isEmpty && !trailingUnderscoreRange.isEmpty) {
        // Both leading and trailing underscores
        result = String(stringKey[leadingUnderscoreRange]) + joinedString + String(stringKey[trailingUnderscoreRange])
    } else if (!leadingUnderscoreRange.isEmpty) {
        // Just leading
        result = String(stringKey[leadingUnderscoreRange]) + joinedString
    } else {
        // Just trailing
        result = joinedString + String(stringKey[trailingUnderscoreRange])
    }
    return result
}

internal var _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()

open class FaultToleranceJSONDecoder {
    public enum FaultStrategy<T> {
        case useDefaultValue(val: T)
    }
    
    public enum FaultStrategyDate<T> {
        case useDefaultValue(val: T)
        case dateUseNow
    }
    
    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    open var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate

    /// The strategy to use in decoding binary data. Defaults to `.base64`.
    open var dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64

    /// The strategy to use for decoding keys. Defaults to `.useDefaultKeys`.
    open var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys

    /// Contextual user-provided information for use during decoding.
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
        let dataDecodingStrategy: JSONDecoder.DataDecodingStrategy
        let keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(dateDecodingStrategy: dateDecodingStrategy,
                        dataDecodingStrategy: dataDecodingStrategy,
                        keyDecodingStrategy: keyDecodingStrategy,
                        userInfo: userInfo)
    }
    
    fileprivate struct _FaultOptions {
        let intToleranceStrategy: FaultStrategy<Int>
        let uintToleranceStrategy: FaultStrategy<UInt>
        
        let floatToleranceStrategy: FaultStrategy<Float>
        let doubleToleranceStrategy: FaultStrategy<Double>
        
        let boolToleranceStrategy: FaultStrategy<Bool>
        let stringToleranceStrategy: FaultStrategy<String>
        
        let dateToleranceStrategy: FaultStrategyDate<Date>
        let dataToleranceStrategy: FaultStrategy<Data>
        
        let urlToleranceStrategy: FaultStrategy<URL>
        let decimalToleranceStrategy: FaultStrategy<Decimal>
    }
    
    fileprivate var faultOptions: _FaultOptions {
        return _FaultOptions(
            intToleranceStrategy: intToleranceStrategy,
            uintToleranceStrategy: uintToleranceStrategy,
            floatToleranceStrategy: floatToleranceStrategy,
            doubleToleranceStrategy: doubleToleranceStrategy,
            boolToleranceStrategy: boolToleranceStrategy,
            stringToleranceStrategy: stringToleranceStrategy,
            dateToleranceStrategy: dateToleranceStrategy,
            dataToleranceStrategy: dataToleranceStrategy,
            urlToleranceStrategy: urlToleranceStrategy,
            decimalToleranceStrategy: decimalToleranceStrategy)
    }
    
    open var intToleranceStrategy: FaultStrategy<Int> = .useDefaultValue(val: 0)
    open var uintToleranceStrategy: FaultStrategy<UInt> = .useDefaultValue(val: 0)
    
    open var floatToleranceStrategy: FaultStrategy<Float> = .useDefaultValue(val: 0.0)
    open var doubleToleranceStrategy: FaultStrategy<Double> = .useDefaultValue(val: 0.0)
    
    open var boolToleranceStrategy: FaultStrategy<Bool> = .useDefaultValue(val: false)
    open var stringToleranceStrategy: FaultStrategy<String> = .useDefaultValue(val: "")
    
    open var dateToleranceStrategy: FaultStrategyDate<Date> = .dateUseNow
    open var dataToleranceStrategy: FaultStrategy<Data> = .useDefaultValue(val: Data())
    
    open var urlToleranceStrategy: FaultStrategy<URL> = .useDefaultValue(val: URL(string: "http://example.com")!)
    open var decimalToleranceStrategy: FaultStrategy<Decimal> = .useDefaultValue(val: Decimal(0))
    
    
    public init() {}
    
    open func decode<T: Decodable>(_ type: T.Type, from data: Data, jsonReadOptions opt: JSONSerialization.ReadingOptions = []) throws -> T {
        do {
            let json = try JSON(data: data, options: opt)
            return try FaultToleranceJSONDecoderImpl(userInfo: [:], from: json, codingPath: [], options: self.options, faultOptons: self.faultOptions).unwrap(as: T.self)
        } catch {
            throw error
        }
    }
    
}


fileprivate struct FaultToleranceJSONDecoderImpl {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    let json: JSON
    let options: FaultToleranceJSONDecoder._Options
    let faultOptons: FaultToleranceJSONDecoder._FaultOptions

    init(userInfo: [CodingUserInfoKey: Any], from json: JSON, codingPath: [CodingKey], options: FaultToleranceJSONDecoder._Options, faultOptons: FaultToleranceJSONDecoder._FaultOptions) {
        self.userInfo = userInfo
        self.codingPath = codingPath
        self.json = json
        self.options = options
        self.faultOptons = faultOptons
    }
    
    // MARK: Special case handling
    func unwrap<T: Decodable>(as type: T.Type) throws -> T {
        if type == Date.self {
            return self.unwrapDate() as! T
        }
        if type == Data.self {
            return self.unwrapData() as! T
        }
        if type == URL.self {
            return self.unwrapURL() as! T
        }
        if type == Decimal.self {
            return self.unwrapDecimal() as! T
        }
        
        if T.self is _CUSJSONStringDictionaryDecodableMarker.Type {
            return try self.unwrapDictionary(as: T.self)
        }

        return try T(from: self)
    }

    private func unwrapDate() -> Date {
        switch self.options.dateDecodingStrategy {
        case .deferredToDate:
            do {
                return try Date(from: self)
            }
            catch {
                debugPrint(error.localizedDescription)
                return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
            }
        case .secondsSince1970:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
            let double = container.decode(Double.self)
            return Date(timeIntervalSince1970: double)

        case .millisecondsSince1970:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
            let double = container.decode(Double.self)
            return Date(timeIntervalSince1970: double / 1000.0)

        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
                let string = container.decode(String.self)
                guard let date = _iso8601Formatter.date(from: string) else {
#if DEBUG
                    let error = DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                    debugPrint(error.localizedDescription)
#endif
                    return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
                }

                return date
            } else {
                return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
            }

        case .formatted(let formatter):
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
            let string = container.decode(String.self)
            guard let date = formatter.date(from: string) else {
#if DEBUG
                let error = DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected by formatter."))
                debugPrint(error.localizedDescription)
#endif
                return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
            }
            return date

        case .custom(let closure):
            do {
                return try closure(self)
            }
            catch {
                debugPrint(error.localizedDescription)
                return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
            }
        @unknown default:
            return defaultValueByOption(option: faultOptons.dateToleranceStrategy)
        }
    }

    private func unwrapData() -> Data {
        switch self.options.dataDecodingStrategy {
        case .deferredToData:
            do {
                return try Data(from: self)
            }
            catch {
                debugPrint(error.localizedDescription)
                return defaultValueByOption(option: faultOptons.dataToleranceStrategy, in: JSON.null)
            }

        case .base64:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
            let string = container.decode(String.self)

            guard let data = Data(base64Encoded: string) else {
#if DEBUG
                let error = DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64."))
                debugPrint(error.localizedDescription)
#endif
                return defaultValueByOption(option: faultOptons.dataToleranceStrategy)
            }

            return data

        case .custom(let closure):
            do {
                return try closure(self)
            }
            catch {
                debugPrint(error.localizedDescription)
                return defaultValueByOption(option: faultOptons.dataToleranceStrategy)
            }
        @unknown default:
            return defaultValueByOption(option: faultOptons.dataToleranceStrategy)
        }
    }

    private func unwrapURL() -> URL {
        let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
        let string = container.decode(String.self)

        guard let url = URL(string: string) else {
#if DEBUG
            let error = DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath,
                                                                          debugDescription: "Invalid URL string."))
            debugPrint(error.localizedDescription)
#endif
            return defaultValueByOption(option: faultOptons.urlToleranceStrategy)
            
        }
        return url
    }
    
    private func unwrapDecimal() -> Decimal {
        guard self.json.type == .number else {
#if DEBUG
            let error = DecodingError.typeMismatch(Decimal.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: ""))
            debugPrint(error.localizedDescription)
#endif
            return defaultValueByOption(option: faultOptons.decimalToleranceStrategy)
        }
        
        return self.json.numberValue.decimalValue
    }

    private func unwrapDictionary<T: Decodable>(as: T.Type) throws -> T {
        guard let dictType = T.self as? (_CUSJSONStringDictionaryDecodableMarker & Decodable).Type else {
            preconditionFailure("Must only be called of T implements _CUSJSONStringDictionaryDecodableMarker")
        }
        
        var result = [String: Any]()

        for (key, value) in self.json.dictionaryValue {
            var newPath = self.codingPath
            newPath.append(_CUSJSONKey(stringValue: key))
            let newDecoder = FaultToleranceJSONDecoderImpl(userInfo: self.userInfo, from: value, codingPath: newPath, options: self.options, faultOptons: self.faultOptons)

            result[key] = try dictType.elementType.createByDirectlyUnwrapping(from: newDecoder)
        }

        return result as! T
    }
    
    fileprivate func defaultValueByOption<T>(option: FaultToleranceJSONDecoder.FaultStrategy<T>, in json: JSON? = nil) -> T {
        guard let json = json else {
            switch option {
            case .useDefaultValue(let val):
                return val
            }
        }
        
        switch option {
        case .useDefaultValue(let val):
            if val is Bool {
                let swiftyJsonValue = json.boolValue
                return swiftyJsonValue == swiftJsonDefaultBoolValue ? val : (swiftyJsonValue as! T)
            } else if val is Int {
                let swiftyJsonValue = json.intValue
                return swiftyJsonValue == swiftJsonDefaultIntValue ? val : (swiftyJsonValue as! T)
            } else if val is UInt {
                let swiftyJsonValue = json.uIntValue
                return swiftyJsonValue == swiftJsonDefaultUIntValue ? val : (swiftyJsonValue as! T)
            } else if val is Float {
                let swiftyJsonValue = json.floatValue
                return swiftyJsonValue == swiftJsonDefaultFloatValue ? val : (swiftyJsonValue as! T)
            } else if val is Double {
                let swiftyJsonValue = json.doubleValue
                return swiftyJsonValue == swiftJsonDefaultDoubleValue ? val : (swiftyJsonValue as! T)
            } else if val is String {
                let swiftyJsonValue = json.stringValue
                return swiftyJsonValue == swiftJsonDefaultStringValue ? val : (swiftyJsonValue as! T)
            } else {
                return val
            }
        }
    }
    
    fileprivate func defaultValueByOption(option: FaultToleranceJSONDecoder.FaultStrategyDate<Date>) -> Date {
        switch option {
        case .useDefaultValue(let val):
            return val
        case .dateUseNow:
            return Date()
        }
    }
}

extension FaultToleranceJSONDecoderImpl: Decoder {
    @usableFromInline func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        switch self.json.type {
        case .dictionary, .null:
            let container = KeyedContainer<Key>(
                impl: self,
                codingPath: codingPath,
                dictionary: json.dictionaryValue
            )
            return KeyedDecodingContainer(container)
        default:
            throw DecodingError.typeMismatch([String: JSON].self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Expected to decode \([String: JSON].self) but found \(self.json.type) instead."
            ))
        }
    }
    
    @usableFromInline func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch self.json.type {
        case .array, .null:
            return UnkeyedContainer(
                impl: self,
                codingPath: self.codingPath,
                array: self.json.arrayValue
            )
        default:
            throw DecodingError.typeMismatch([JSON].self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Expected to decode \([JSON].self) but found \(self.json.type) instead."
            ))
        }
    }
    
    @usableFromInline func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueContainer(
            impl: self,
            codingPath: self.codingPath,
            json: self.json
        )
    }
}

extension FaultToleranceJSONDecoderImpl {
    struct KeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
        typealias Key = K
        
        let impl: FaultToleranceJSONDecoderImpl
        let codingPath: [CodingKey]
        let dictionary: [String: JSON]
        
        init(impl: FaultToleranceJSONDecoderImpl, codingPath: [CodingKey], dictionary: [String: JSON]) {
            self.impl = impl
            self.codingPath = codingPath
            
            switch impl.options.keyDecodingStrategy {
            case .useDefaultKeys:
                self.dictionary = dictionary
            case .convertFromSnakeCase:
                // Convert the snake case keys in the container to camel case.
                // If we hit a duplicate key after conversion, then we'll use the first one we saw.
                // Effectively an undefined behavior with JSON dictionaries.
                var converted = [String: JSON]()
                converted.reserveCapacity(dictionary.count)
                dictionary.forEach { (key, value) in
                    converted[_cusConvertFromSnakeCase(key)] = value
                }
                self.dictionary = converted
            case .custom(let converter):
                var converted = [String: JSON]()
                converted.reserveCapacity(dictionary.count)
                dictionary.forEach { (key, value) in
                    var pathForKey = codingPath
                    pathForKey.append(_CUSJSONKey(stringValue: key))
                    converted[converter(pathForKey).stringValue] = value
                }
                self.dictionary = converted
            @unknown default:
                self.dictionary = dictionary
                break
            }
        }
        
        var allKeys: [K] {
            self.dictionary.keys.compactMap { K(stringValue: $0) }
        }
        
        func contains(_ key: K) -> Bool {
            if let _ = dictionary[key.stringValue] {
                return true
            }
            return false
        }
        
        func decodeNil(forKey key: K) -> Bool {
            let value = getValue(forKey: key)
            return value.type == .null
        }
        
        func decode(_ type: Bool.Type, forKey key: K) -> Bool {
            let value = getValue(forKey: key)
            return value.bool ?? impl.defaultValueByOption(option: impl.faultOptons.boolToleranceStrategy, in: value)
        }
        
        func decode(_ type: String.Type, forKey key: K) -> String {
            let value = getValue(forKey: key)
            return value.string ?? impl.defaultValueByOption(option: impl.faultOptons.stringToleranceStrategy, in: value)
        }
        
        func decode(_: Double.Type, forKey key: K) -> Double {
            let value = getValue(forKey: key)
            return value.double ?? impl.defaultValueByOption(option: impl.faultOptons.doubleToleranceStrategy, in: value)
        }
        
        func decode(_: Float.Type, forKey key: K) -> Float {
            let value = getValue(forKey: key)
            return value.float ?? impl.defaultValueByOption(option: impl.faultOptons.floatToleranceStrategy, in: value)
        }
        
        func decode(_: Int.Type, forKey key: K) -> Int {
            let value = getValue(forKey: key)
            return value.int ?? impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value)
        }
        
        func decode(_: Int8.Type, forKey key: K) -> Int8 {
            let value = getValue(forKey: key)
            return value.int8 ?? Int8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        func decode(_: Int16.Type, forKey key: K) -> Int16 {
            let value = getValue(forKey: key)
            return value.int16 ?? Int16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        func decode(_: Int32.Type, forKey key: K) -> Int32 {
            let value = getValue(forKey: key)
            return value.int32 ?? Int32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        func decode(_: Int64.Type, forKey key: K) -> Int64 {
            let value = getValue(forKey: key)
            return value.int64 ?? Int64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        func decode(_: UInt.Type, forKey key: K) -> UInt {
            let value = getValue(forKey: key)
            return value.uInt ?? impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value)
        }
        
        func decode(_: UInt8.Type, forKey key: K) -> UInt8 {
            let value = getValue(forKey: key)
            return value.uInt8 ?? UInt8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        func decode(_: UInt16.Type, forKey key: K) -> UInt16 {
            let value = getValue(forKey: key)
            return value.uInt16 ?? UInt16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        func decode(_: UInt32.Type, forKey key: K) -> UInt32 {
            let value = getValue(forKey: key)
            return value.uInt32 ?? UInt32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        func decode(_: UInt64.Type, forKey key: K) -> UInt64 {
            let value = getValue(forKey: key)
            return value.uInt64 ?? UInt64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        func decode<T>(_: T.Type, forKey key: K) throws -> T where T: Decodable {
            let newDecoder = decoderForKey(key)
            return try newDecoder.unwrap(as: T.self)
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            try decoderForKey(key).container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
            try decoderForKey(key).unkeyedContainer()
        }
        
        func superDecoder() throws -> Decoder {
            return decoderForKey(_CUSJSONKey.super)
        }
        
        func superDecoder(forKey key: K) throws -> Decoder {
            return decoderForKey(key)
        }
        
        private func decoderForKey<LocalKey: CodingKey>(_ key: LocalKey) -> FaultToleranceJSONDecoderImpl {
            let value = getValue(forKey: key)
            var newPath = self.codingPath
            newPath.append(key)
            
            return FaultToleranceJSONDecoderImpl(
                userInfo: self.impl.userInfo,
                from: value,
                codingPath: newPath,
                options: self.impl.options,
                faultOptons: self.impl.faultOptons
            )
        }
        
        @inline(__always) private func getValue<LocalKey: CodingKey>(forKey key: LocalKey) -> JSON {
            return dictionary[key.stringValue] ?? .null
        }
        
        // MARK: decode if present
        public func decodeIfPresent(_ type: Bool.Type, forKey key: Self.Key) -> Bool? {
            let value = getValue(forKey: key)
            return value.bool
        }
        
        
        public func decodeIfPresent(_ type: String.Type, forKey key: Self.Key) -> String? {
            getValue(forKey: key).string
        }
        
        public func decodeIfPresent(_ type: Double.Type, forKey key: Self.Key) -> Double? {
            getValue(forKey: key).double
        }
        
        public func decodeIfPresent(_ type: Float.Type, forKey key: Self.Key) -> Float? {
            getValue(forKey: key).float
        }
        
        public func decodeIfPresent(_ type: Int.Type, forKey key: Self.Key) -> Int? {
            getValue(forKey: key).int
        }
        
        public func decodeIfPresent(_ type: Int8.Type, forKey key: Self.Key) -> Int8? {
            getValue(forKey: key).int8
        }
        public func decodeIfPresent(_ type: Int16.Type, forKey key: Self.Key) -> Int16? {
            getValue(forKey: key).int16
        }
        
        public func decodeIfPresent(_ type: Int32.Type, forKey key: Self.Key) -> Int32? {
            getValue(forKey: key).int32
        }
        
        public func decodeIfPresent(_ type: Int64.Type, forKey key: Self.Key) -> Int64? {
            getValue(forKey: key).int64
            
        }
        
        public func decodeIfPresent(_ type: UInt.Type, forKey key: Self.Key) -> UInt? {
            getValue(forKey: key).uInt
        }
        
        public func decodeIfPresent(_ type: UInt8.Type, forKey key: Self.Key) -> UInt8? {
            getValue(forKey: key).uInt8
        }
        
        public func decodeIfPresent(_ type: UInt16.Type, forKey key: Self.Key) -> UInt16? {
            getValue(forKey: key).uInt16
        }
        
        public func decodeIfPresent(_ type: UInt32.Type, forKey key: Self.Key) -> UInt32? {
            getValue(forKey: key).uInt32
        }
        
        public func decodeIfPresent(_ type: UInt64.Type, forKey key: Self.Key) -> UInt64? {
            getValue(forKey: key).uInt64
        }
        
        public func decodeIfPresent<T>(_ type: T.Type, forKey key: Self.Key) throws -> T? where T : Decodable {
            guard getValue(forKey: key).type != .null else {
                return nil
            }
            
            let newDecoder = decoderForKey(key)
            return try newDecoder.unwrap(as: T.self)
        }
    }
}

extension FaultToleranceJSONDecoderImpl {
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        let impl: FaultToleranceJSONDecoderImpl
        let codingPath: [CodingKey]
        let array: [JSON]
        
        var count: Int? { self.array.count }
        var isAtEnd: Bool { self.currentIndex >= (self.count ?? 0) }
        var currentIndex = 0
        
        init(impl: FaultToleranceJSONDecoderImpl, codingPath: [CodingKey], array: [JSON]) {
            self.impl = impl
            self.codingPath = codingPath
            self.array = array
        }
        
        mutating func decodeNil() throws -> Bool {
            if try self.getNextValue(ofType: Never.self) == .null {
                self.currentIndex += 1
                return true
            }
            
            // The protocol states:
            //   If the value is not null, does not increment currentIndex.
            return false
        }
        
        mutating func decode(_ type: Bool.Type) throws -> Bool {
            let value = try self.getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.bool ?? impl.defaultValueByOption(option: impl.faultOptons.boolToleranceStrategy)
        }
        
        mutating func decode(_ type: String.Type) throws -> String {
            let value = try self.getNextValue(ofType: String.self)
            
            self.currentIndex += 1
            return value.string ?? impl.defaultValueByOption(option: impl.faultOptons.stringToleranceStrategy, in: value)
        }
        
        mutating func decode(_: Double.Type) throws -> Double {
            let value = try self.getNextValue(ofType: Double.self)
            
            self.currentIndex += 1
            return value.double ?? impl.defaultValueByOption(option: impl.faultOptons.doubleToleranceStrategy, in: value)
        }
        
        mutating func decode(_: Float.Type) throws -> Float {
            let value = try self.getNextValue(ofType: Float.self)
            
            self.currentIndex += 1
            return value.float ?? impl.defaultValueByOption(option: impl.faultOptons.floatToleranceStrategy, in: value)
        }
        
        mutating func decode(_: Int.Type) throws -> Int {
            let value = try self.getNextValue(ofType: Int.self)
            
            self.currentIndex += 1
            return value.int ?? impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value)
        }
        
        mutating func decode(_: Int8.Type) throws -> Int8 {
            let value = try self.getNextValue(ofType: Int8.self)
            
            self.currentIndex += 1
            return value.int8 ?? Int8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        mutating func decode(_: Int16.Type) throws -> Int16 {
            let value = try self.getNextValue(ofType: Int16.self)
            
            self.currentIndex += 1
            return value.int16 ?? Int16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        mutating func decode(_: Int32.Type) throws -> Int32 {
            let value = try self.getNextValue(ofType: Int32.self)
            
            self.currentIndex += 1
            return value.int32 ?? Int32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        mutating func decode(_: Int64.Type) throws -> Int64 {
            let value = try self.getNextValue(ofType: Int64.self)
            
            self.currentIndex += 1
            return value.int64 ?? Int64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }
        
        mutating func decode(_: UInt.Type) throws -> UInt {
            let value = try self.getNextValue(ofType: UInt.self)
            
            self.currentIndex += 1
            return value.uInt ?? impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value)
        }
        
        mutating func decode(_: UInt8.Type) throws -> UInt8 {
            let value = try self.getNextValue(ofType: UInt8.self)
            
            self.currentIndex += 1
            return value.uInt8 ?? UInt8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        mutating func decode(_: UInt16.Type) throws -> UInt16 {
            let value = try self.getNextValue(ofType: UInt16.self)
            
            self.currentIndex += 1
            return value.uInt16 ?? UInt16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        mutating func decode(_: UInt32.Type) throws -> UInt32 {
            let value = try self.getNextValue(ofType: UInt32.self)
            
            self.currentIndex += 1
            return value.uInt32 ?? UInt32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        mutating func decode(_: UInt64.Type) throws -> UInt64 {
            let value = try self.getNextValue(ofType: UInt64.self)
            
            self.currentIndex += 1
            return value.uInt64 ?? UInt64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }
        
        mutating func decode<T>(_: T.Type) throws -> T where T: Decodable {
            let newDecoder = try decoderForNextElement(ofType: T.self)
            let result = try newDecoder.unwrap(as: T.self)
            
            // Because of the requirement that the index not be incremented unless
            // decoding the desired result type succeeds, it can not be a tail call.
            // Hopefully the compiler still optimizes well enough that the result
            // doesn't get copied around.
            self.currentIndex += 1
            return result
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            let decoder = try decoderForNextElement(ofType: KeyedDecodingContainer<NestedKey>.self)
            let container = try decoder.container(keyedBy: type)
            
            self.currentIndex += 1
            return container
        }
        
        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let decoder = try decoderForNextElement(ofType: UnkeyedDecodingContainer.self)
            let container = try decoder.unkeyedContainer()
            
            self.currentIndex += 1
            return container
        }
        
        mutating func superDecoder() throws -> Decoder {
            let decoder = try decoderForNextElement(ofType: Decoder.self)
            self.currentIndex += 1
            return decoder
        }
        
        private mutating func decoderForNextElement<T>(ofType: T.Type) throws -> FaultToleranceJSONDecoderImpl {
            let value = try self.getNextValue(ofType: T.self)
            let newPath = self.codingPath + [_CUSJSONKey(index: self.currentIndex)]
            
            return FaultToleranceJSONDecoderImpl(
                userInfo: self.impl.userInfo,
                from: value,
                codingPath: newPath,
                options: self.impl.options,
                faultOptons: self.impl.faultOptons
            )
        }
        
        @inline(__always)
        private func getNextValue<T>(ofType: T.Type) throws -> JSON {
            guard !self.isAtEnd else {
                var message = "Unkeyed container is at end."
                if T.self == UnkeyedContainer.self {
                    message = "Cannot get nested unkeyed container -- unkeyed container is at end."
                }
                if T.self == Decoder.self {
                    message = "Cannot get superDecoder() -- unkeyed container is at end."
                }
                
                var path = self.codingPath
                path.append(_CUSJSONKey(index: self.currentIndex))
                
                throw DecodingError.valueNotFound(
                    T.self,
                    .init(codingPath: path,
                          debugDescription: message,
                          underlyingError: nil))
            }
            return self.array[self.currentIndex]
        }
        
        // MARK: decode if present
        public mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.bool
        }
        
        public mutating func decodeIfPresent(_ type: String.Type) throws -> String? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.string
        }
        
        public mutating func decodeIfPresent(_ type: Double.Type) throws -> Double? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.double
        }
        
        public mutating func decodeIfPresent(_ type: Float.Type) throws -> Float? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.float
        }
        
        public mutating func decodeIfPresent(_ type: Int.Type) throws -> Int? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.int
        }
        
        public mutating func decodeIfPresent(_ type: Int8.Type) throws -> Int8? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.int8
        }
        
        public mutating func decodeIfPresent(_ type: Int16.Type) throws -> Int16? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.int16
        }
        
        public mutating func decodeIfPresent(_ type: Int32.Type) throws -> Int32? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.int32
        }
        
        public mutating func decodeIfPresent(_ type: Int64.Type) throws -> Int64? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.int64
        }
        
        public mutating func decodeIfPresent(_ type: UInt.Type) throws -> UInt? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.uInt
        }
        
        public mutating func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.uInt8
        }
        
        public mutating func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.uInt16
        }
        
        public mutating func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.uInt32
        }
        
        public mutating func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? {
            let value = try getNextValue(ofType: Bool.self)
            
            self.currentIndex += 1
            return value.uInt64
        }
        
        public mutating func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T : Decodable {
            let value = try self.getNextValue(ofType: T.self)
            if value.type == .null {
                self.currentIndex += 1
                return nil
            }
            
            let newDecoder = try decoderForNextElement(ofType: T.self)
            let result = try newDecoder.unwrap(as: T.self)
            
            // Because of the requirement that the index not be incremented unless
            // decoding the desired result type succeeds, it can not be a tail call.
            // Hopefully the compiler still optimizes well enough that the result
            // doesn't get copied around.
            self.currentIndex += 1
            return result
        }
        
    }
}

extension FaultToleranceJSONDecoderImpl {
    struct SingleValueContainer: SingleValueDecodingContainer {
        let impl: FaultToleranceJSONDecoderImpl
        let value: JSON
        let codingPath: [CodingKey]

        init(impl: FaultToleranceJSONDecoderImpl, codingPath: [CodingKey], json: JSON) {
            self.impl = impl
            self.codingPath = codingPath
            self.value = json
        }

        func decodeNil() -> Bool {
            self.value == .null
        }

        func decode(_: Bool.Type) -> Bool {
            return value.bool ?? impl.defaultValueByOption(option: impl.faultOptons.boolToleranceStrategy, in: value)
        }

        func decode(_: String.Type) -> String {
            return value.string ?? impl.defaultValueByOption(option: impl.faultOptons.stringToleranceStrategy, in: value)
        }

        func decode(_: Double.Type) -> Double {
            return value.double ?? impl.defaultValueByOption(option: impl.faultOptons.doubleToleranceStrategy, in: value)
        }

        func decode(_: Float.Type) -> Float {
            return value.float ?? impl.defaultValueByOption(option: impl.faultOptons.floatToleranceStrategy, in: value)
        }

        func decode(_: Int.Type) -> Int {
            return value.int ?? impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value)
        }

        func decode(_: Int8.Type) -> Int8 {
            return value.int8 ?? Int8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }

        func decode(_: Int16.Type) -> Int16 {
            return value.int16 ?? Int16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }

        func decode(_: Int32.Type) -> Int32 {
            return value.int32 ?? Int32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }

        func decode(_: Int64.Type) -> Int64 {
            return value.int64 ?? Int64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.intToleranceStrategy, in: value))
        }

        func decode(_: UInt.Type) -> UInt {
            return value.uInt ?? impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value)
        }

        func decode(_: UInt8.Type) -> UInt8 {
            return value.uInt8 ?? UInt8(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }

        func decode(_: UInt16.Type) -> UInt16 {
            return value.uInt16 ?? UInt16(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }

        func decode(_: UInt32.Type) -> UInt32 {
            return value.uInt32 ?? UInt32(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }

        func decode(_: UInt64.Type) -> UInt64 {
            return value.uInt64 ?? UInt64(truncatingIfNeeded: impl.defaultValueByOption(option: impl.faultOptons.uintToleranceStrategy, in: value))
        }

        func decode<T>(_: T.Type) throws -> T where T: Decodable {
            try self.impl.unwrap(as: T.self)
        }
    }
}


// MARK: SwiftJSON default value
fileprivate let swiftJsonDefaultBoolValue: Bool = false
fileprivate let swiftJsonDefaultIntValue: Int = 0
fileprivate let swiftJsonDefaultUIntValue: UInt = 0
fileprivate let swiftJsonDefaultFloatValue: Float = 0.0
fileprivate let swiftJsonDefaultDoubleValue: Double = 0.0
fileprivate let swiftJsonDefaultStringValue: String = ""
