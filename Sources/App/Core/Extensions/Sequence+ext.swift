// Copyright 2020-2021 Dave Verwer, Sven A. Schmidt, and other contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


extension Sequence {
    func mapAsync<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results = [T]()
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}


//extension Result {
//    func mapAsync<NewSuccess, NewFailure>(_ transform: (Success) async throws -> NewSuccess) async -> Result<NewSuccess, NewFailure> where NewFailure == any Error {
//        switch self {
//            case .success(let success):
//                do {
//                    return try await .success(transform(success))
//                } catch {
//                    return .failure(error)
//                }
//            case .failure(let failure):
//                return .failure(failure)
//        }
//    }
//}
