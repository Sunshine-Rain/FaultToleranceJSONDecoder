# FaultToleranceJSONDecoder

A json decoder has fault tolerance. Most of codes are based on [JSONDecoder.swift](https://github.com/apple/swift-corelibs-foundation/blob/9c4cec91fe344dd25c23aa1971eb36f926bfcaf4/Sources/Foundation/JSONDecoder.swift).

### Dependency

* SwiftyJSON

### Usage

* Install dependencies using cocoapods or carthage.
* Drag Source Code to your project.
* Use as swift JSONDecoder. 

```
struct Landmark: Codable {
    var name: String
    var age: Int
    var isCommander: Bool
    
    enum CodingKeys: String, CodingKey {
        case name = "__name"
        case age = "age"
        case isCommander = "isCommander"
    }
}


let landmarkStr = """
{
    "__name" : "Hello",
    "age" : 18,
    "isCommander" : null
}
"""

let jsonDecoder = FaultToleranceJSONDecoder()
let model = try! jsonDecoder.decode(String.self, from: landmarkStr.data(using: .utf8)!)
print(model)
```
