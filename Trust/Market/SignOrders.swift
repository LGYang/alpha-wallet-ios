import BigInt
import TrustKeystore
import Trust

public struct Order {
    var price: BigInt
    var ticketIndices: [UInt16]
    var expiryTimeStamp: BigInt
    var contractAddress: String
}

public struct SignedOrder {
    var order : Order
    var message : Data
    var signature : String
}

extension String {
    var hexa2Bytes: [UInt8] {
        let hexa = Array(characters)
        return stride(from: 0, to: count, by: 2).flatMap { UInt8(String(hexa[$0..<$0.advanced(by: 2)]), radix: 16) }
    }
}

extension BinaryInteger {
    var data: Data {
        var source = self
        return Data(bytes: &source, count: MemoryLayout<Self>.size)
    }
}

extension Data {
    var array: [UInt8] { return Array(self) }
}

public class SignOrders {

    private let keyStore = try! EtherKeystore()

    //takes a list of orders and returns a list of signature objects
    func signOrders(orders : Array<Order>, account : Account) -> Array<SignedOrder> {
        var signedOrders : Array<SignedOrder> = Array<SignedOrder>()
        //EtherKeystore.signMessage(encodeMessage(), )
        for i in 0...orders.count - 1 {
            //sign each order
            //TODO check casting to string
            let message : [UInt8] = encodeMessageForTrade(price: orders[i].price,
                    expiryTimestamp: orders[i].expiryTimeStamp, tickets: orders[i].ticketIndices,
                    contractAddress : orders[i].contractAddress)
            let messageData = Data(bytes: message)

            let signature = try! keyStore.signMessageData(messageData, for: account)
            let signedOrder : SignedOrder = try! SignedOrder(order : orders[i], message: messageData,
                    signature : signature.description)
            signedOrders.append(signedOrder)
        }
        return signedOrders
    }

    //TODO fix this encoding as it doesn't match solidity ecrecover
    //price is casted wrong
    func encodeMessageForTrade(price : BigInt, expiryTimestamp : BigInt,
                               tickets : [UInt16], contractAddress : String) -> [UInt8]
    {
        //ticket count * 2 because it is 16 bits not 8
        let arrayLength: Int = 84 + tickets.count * 2
        var buffer = [UInt8]()
        buffer.reserveCapacity(arrayLength)
        //TODO represent as Uint16 and cast back into uint8
        var priceInWei = [UInt8] (price.description.utf8)
        for i in 0...31 - priceInWei.count {
            //pad with zeros
            priceInWei.insert(0, at: 0)
        }
        for i in 0...31 {
            buffer.append(0)//priceInWei[i])
        }

        var expiryBuffer = [UInt8] (expiryTimestamp.description.utf8)

        for i in 0...31 - expiryBuffer.count {
            expiryBuffer.insert(0, at: 0)
        }

        for i in 0...31 {
            buffer.append(0)//expiryBuffer[i])
        }
        //no leading zeros issue here
        var contractAddr = contractAddress.hexa2Bytes

        for i in 0...19 {
            buffer.append(contractAddr[i])
        }

        var ticketsUint8 = uInt16ArrayToUInt8(arrayOfUInt16: tickets)

        for i in 0...ticketsUint8.count - 1 {
            buffer.append(ticketsUint8[i])
        }

        return buffer
    }

    func uInt16ArrayToUInt8(arrayOfUInt16: [UInt16]) -> [UInt8]
    {
        var arrayOfUint8 : [UInt8] = [UInt8]()
        for i in 0...arrayOfUInt16.count - 1 {
            var UInt8ArrayPair = arrayOfUInt16[i].bigEndian.data.array
            arrayOfUint8.append(UInt8ArrayPair[0])
            arrayOfUint8.append(UInt8ArrayPair[1])
        }
        return arrayOfUint8
    }

    func bufferToString(buffer : [UInt8]) -> String
    {
        var bufferString : String = "";
        for i in 0...buffer.count - 1 {
            bufferString += String(buffer[i])
        }
        return bufferString
    }

}
