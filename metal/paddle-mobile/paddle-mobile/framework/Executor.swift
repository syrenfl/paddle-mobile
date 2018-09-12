/* Copyright (c) 2018 PaddlePaddle Authors. All Rights Reserved.
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License. */

import Foundation

let testTo = 3
var isTest = false

let computePrecision: ComputePrecision = .Float16

public class ResultHolder {
  public let dim: [Int]
  public let resultArr: [Float32]
  public var intermediateResults: [String : [Variant]]?
  public let elapsedTime: Double
  public init(inDim: [Int], inResult: [Float32], inElapsedTime: Double, inIntermediateResults: [String : [Variant]]? = nil) {
    dim = inDim
    resultArr = inResult
    elapsedTime = inElapsedTime
    intermediateResults = inIntermediateResults
  }
}

extension ResultHolder: CustomDebugStringConvertible, CustomStringConvertible {
  public var debugDescription: String {
    var str = ""
    str += "Dim: \(dim) \n value:[ "
    if resultArr.count < 20 {
      for d in resultArr {
        str += " \(d) "
      }
    } else {
      for d in stride(from: 0, to: resultArr.count, by: resultArr.count/20) {
        str += " \(resultArr[d]) "
      }
    }
    str += " ]"
    return str
  }
  
  public var description: String {
    return debugDescription
  }
}

public class Executor<P: PrecisionType> {
  var ops: [Runable & InferShaperable] = []
  let program: Program
  let device: MTLDevice
  let inflightSemaphore: DispatchSemaphore
  let queue: MTLCommandQueue
  public init(inDevice:MTLDevice, inQueue: MTLCommandQueue, inProgram: Program) throws {
    self.inflightSemaphore = DispatchSemaphore(value: 3)
    program = inProgram
    device = inDevice
    queue = inQueue
    for block in inProgram.programDesc.blocks {
      //block.ops.count
      for i in 0..<block.ops.count {
        let op = block.ops[i]
        do {
          let op = try OpCreator<P>.shared.creat(device: inDevice, opDesc: op, scope: inProgram.scope)
          ops.append(op)
        } catch let error {
          throw error
        }
      }
    }
  }
  
  public func predict(input: MTLTexture, dim: [Int], completionHandle: @escaping (ResultHolder) -> Void, preProcessKernle: CusomKernel? = nil, except: Int = 0) throws {
    guard let buffer = queue.makeCommandBuffer() else {
      throw PaddleMobileError.predictError(message: "CommandBuffer is nil")
    }
    inflightSemaphore.wait()
    
    let resInput: MTLTexture
    if let inPre = preProcessKernle {
      do {
        try inPre.compute(inputTexuture: input, commandBuffer: buffer)
        resInput = inPre.outputTexture
      } catch let error {
        throw error
      }
    } else {
      resInput = input
    }
    
    let beforeDate = Date.init()
    let inputTexture = InputTexture.init(inMTLTexture: resInput, inExpectDim: Dim.init(inDim: dim))
    program.scope.setInput(input: inputTexture)
    //(ops.count - except)
    for i in 0..<ops.count {
      let op = ops[i]
      do {
        try op.run(device: device, buffer: buffer)
      } catch let error {
        throw error
      }
    }
    
    var outputTextures: [String : [Variant]]?
    if except > 0 {
      outputTextures = ops[ops.count - except].inputVariant()
    }
    
    buffer.addCompletedHandler { [weak self] (commandbuffer) in
      
//      let inputArr = resInput.toTensor(dim: (n: dim[0], c: dim[3], h: dim[1], w: dim[2]))
////      print(inputArr.strideArray())

//      print(dim)
//      writeToLibrary(fileName: "test_image_ssd_ar", array: inputArr)
      
//      print("write to library done")
//      return
      //            print(inputArr)
      
      //            let stridableInput: [(index: Int, value: Float)] = input.stridableFloatArray()
      //            print(stridableInput)
      
      //            let _: Flo? = input.logDesc(header: "input: ", stridable: true)
//      for i in 0..<self.ops.count {
//        let op = self.ops[i]
//        print(" 第 \(i) 个 op: ")
//        op.delogOutput()
//      }
      
//      return;
//      self.ops[testTo - 2].delogOutput()
//      self.ops[testTo - 1].delogOutput()
//      self.ops[60].delogOutput()

//      return
      
      guard let SSelf = self else {
        fatalError()
      }
      
      let afterDate = Date.init()
      var resultHolder: ResultHolder
      if except > 0 {
        resultHolder = ResultHolder.init(inDim: [], inResult: [], inElapsedTime: afterDate.timeIntervalSince(beforeDate), inIntermediateResults: outputTextures)
      } else {
        let outputVar: Variant = SSelf.program.scope.output()!
        let output: Texture<P> = outputVar as! Texture<P>
        
        resultHolder = ResultHolder.init(inDim: output.dim.dims, inResult: output.toTensor(), inElapsedTime: afterDate.timeIntervalSince(beforeDate))
      }

      completionHandle(resultHolder)
      SSelf.inflightSemaphore.signal()
    }
    buffer.commit()
  }
  
  public func clear() {
    program.scope.clear()
  }
  
}

//public let paddle_executor: Executor = Executor.init()